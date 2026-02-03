class Captain::Conversation::ResponseBuilderJob < ApplicationJob
  MAX_MESSAGE_LENGTH = 10_000
  retry_on ActiveStorage::FileNotFoundError, attempts: 3, wait: 2.seconds
  retry_on Faraday::BadRequestError, attempts: 3, wait: 2.seconds

  def perform(conversation, assistant)
    @conversation = conversation
    @inbox = conversation.inbox
    @assistant = assistant

    Current.executed_by = @assistant

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    captain_logger.info("[Captain][ResponseBuilderJob] start conversation_id=#{@conversation.id} assistant_id=#{@assistant.id} inbox_id=#{@inbox.id}")
    if streaming_enabled?
      generate_and_process_response
    else
      ActiveRecord::Base.transaction do
        generate_and_process_response
      end
    end
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    captain_logger.info("[Captain][ResponseBuilderJob] completed in #{elapsed_ms}ms conversation_id=#{@conversation.id}")
  rescue StandardError => e
    raise e if e.is_a?(ActiveStorage::FileNotFoundError) || e.is_a?(Faraday::BadRequestError)

    handle_error(e)
  ensure
    # Always clean up streaming message if it exists and wasn't finalized
    cleanup_streaming_message
    Current.executed_by = nil
  end

  private

  delegate :account, :inbox, to: :@conversation

  def generate_and_process_response
    history_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    message_history = collect_previous_messages
    history_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - history_start) * 1000).round
    captain_logger.info("[Captain][ResponseBuilderJob] message_history size=#{message_history.length} in #{history_elapsed_ms}ms conversation_id=#{@conversation.id}")

    response_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    used_streaming = false
    if streaming_enabled? && !captain_v2_enabled?
      captain_logger.info('[Captain][ResponseBuilderJob] using v1 assistant chat with streaming')
      @streaming_message = create_streaming_message
      used_streaming = true
      start_typing_indicator
      @response = Captain::Llm::AssistantChatService.new(assistant: @assistant, conversation: @conversation).generate_response(
        message_history: message_history,
        stream: true,
        on_chunk: method(:handle_stream_chunk)
      )
      finalize_streaming_message
    else
      @response = if captain_v2_enabled?
                    captain_logger.info('[Captain][ResponseBuilderJob] using v2 agent runner')
                    Captain::Assistant::AgentRunnerService.new(assistant: @assistant, conversation: @conversation).generate_response(
                      message_history: message_history
                    )
                  else
                    captain_logger.info('[Captain][ResponseBuilderJob] using v1 assistant chat')
                    Captain::Llm::AssistantChatService.new(assistant: @assistant, conversation: @conversation).generate_response(
                      message_history: message_history
                    )
                  end
    end
    response_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - response_start) * 1000).round
    captain_logger.info("[Captain][ResponseBuilderJob] response_generated in #{response_elapsed_ms}ms conversation_id=#{@conversation.id}")

    return process_action('handoff') if handoff_requested?

    create_messages unless used_streaming
    captain_logger.info("[Captain][ResponseBuilderJob] Incrementing response usage for account_id=#{account.id}")
    account.increment_response_usage
  end

  def collect_previous_messages
    @conversation
      .messages
      .where(message_type: [:incoming, :outgoing])
      .where(private: false)
      .reorder(created_at: :desc)
      .limit(20)
      .to_a
      .reverse
      .map do |message|
      content = prepare_multimodal_message_content(message)
      role = determine_role(message)

      content = format_assistant_content(content) if role == 'assistant' && content.is_a?(String)

      message_hash = {
        content: content,
        role: role
      }

      # Include agent_name if present in additional_attributes
      message_hash[:agent_name] = message.additional_attributes['agent_name'] if message.additional_attributes&.dig('agent_name').present?

      message_hash
    end
  end

  def format_assistant_content(content)
    # Try parsing to check if it's already JSON
    JSON.parse(content)
    content
  rescue JSON::ParserError
    {
      reasoning: 'Derived from conversation history',
      response: content
    }.to_json
  end

  def determine_role(message)
    message.message_type == 'incoming' ? 'user' : 'assistant'
  end

  def prepare_multimodal_message_content(message)
    Captain::OpenAiMessageBuilderService.new(message: message).generate_content
  end

  def handoff_requested?
    @response['response'] == 'conversation_handoff'
  end

  def process_action(action)
    case action
    when 'handoff'
      I18n.with_locale(@assistant.account.locale) do
        create_handoff_message
        @conversation.bot_handoff!
      end
    end
  end

  def create_handoff_message
    base_message = @assistant.config['handoff_message'].presence || I18n.t('conversations.captain.handoff')

    translated_message = Llm::TranslationService.new(@conversation).translate_message(base_message)
    create_outgoing_message(translated_message)
  end

  def create_messages
    validate_message_content!(@response['response'])
    create_outgoing_message(@response['response'], agent_name: @response['agent_name'])
  end

  def validate_message_content!(content)
    raise ArgumentError, 'Message content cannot be blank' if content.blank?
  end

  def create_outgoing_message(message_content, agent_name: nil)
    additional_attrs = {}
    additional_attrs[:agent_name] = agent_name if agent_name.present?

    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: @assistant,
      content: message_content,
      additional_attributes: additional_attrs
    )
  end

  def create_streaming_message
    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: @assistant,
      content: '',
      additional_attributes: { streaming: true }
    )
  end

  def handle_stream_chunk(full_content, delta_content)
    return unless @streaming_message
    return if delta_content.blank?

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @last_stream_update_at ||= now
    @last_stream_length ||= 0

    # Try to extract just the "response" field from JSON content
    # This prevents showing the "reasoning" field to users during streaming
    display_content = extract_response_for_streaming(full_content)
    display_content = strip_streaming_citations(display_content)

    return if display_content.blank?

    should_update = (display_content.length - @last_stream_length) >= 40 ||
                    (now - @last_stream_update_at) >= 0.25

    return unless should_update

    @streaming_message.update!(content: display_content)
    stop_typing_indicator
    @last_stream_update_at = now
    @last_stream_length = display_content.length
  rescue StandardError => e
    captain_logger.warn("[Captain][ResponseBuilderJob] stream update failed: #{e.message}")
  end

  def extract_response_for_streaming(content)
    # Try to extract just the response portion from JSON
    # The LLM returns: {"reasoning":"...", "response":"..."}
    # We only want to show the "response" part to users

    # First, try to parse as complete JSON
    begin
      parsed = JSON.parse(content)
      return parsed['response'] || content if parsed.is_a?(Hash) && parsed['response']
    rescue JSON::ParserError
      # Not complete JSON yet, try regex extraction
    end

    # Try to extract partial response using regex
    # Look for "response": "..." pattern and extract content
    if (match = content.match(/"response"\s*:\s*"((?:[^"\\]|\\.)*)/))
      # Unescape the captured string
      extracted = match[1].gsub('\\n', "\n").gsub('\"', '"').gsub('\\\\', '\\')
      return extracted if extracted.present?
    end

    # If we can see "reasoning" but haven't started "response" yet, keep empty
    return '' if content.include?('"reasoning"') && !content.include?('"response"')

    # Avoid exposing raw JSON to the user while streaming
    return '' if content.strip.start_with?('{')

    # Fallback: return original content only if it looks like plain text
    content
  end

  def strip_streaming_citations(content)
    return content if content.blank?

    content
      .gsub(/\s*\[\[\d+\]\([^)]+\)\]/, '')
      .gsub(/\s*\[(\d+)\]/, '')
  end

  def finalize_streaming_message
    return unless @streaming_message

    if handoff_requested?
      # Mark as deleted to trigger MESSAGE_UPDATED event for frontend, then destroy
      destroy_streaming_message
      stop_typing_indicator
      return
    end

    final_content = @response['response'].to_s
    validate_message_content!(final_content)
    attrs = (@streaming_message.additional_attributes || {}).merge('streaming' => false)
    attrs['agent_name'] = @response['agent_name'] if @response['agent_name'].present?
    @streaming_message.update!(content: final_content, additional_attributes: attrs)
    @streaming_message = nil
    stop_typing_indicator
  end

  def start_typing_indicator
    return if @typing_indicator_on

    toggle_typing_indicator('on')
    @typing_indicator_on = true
  end

  def stop_typing_indicator
    return unless @typing_indicator_on

    toggle_typing_indicator('off')
    @typing_indicator_on = false
  end

  def toggle_typing_indicator(status)
    Conversations::TypingStatusManager.new(
      @conversation,
      @assistant,
      { typing_status: status, is_private: false }
    ).toggle_typing_status
  rescue StandardError => e
    captain_logger.warn("[Captain][ResponseBuilderJob] typing indicator failed: #{e.message}")
  end

  def handle_error(error)
    log_error(error)
    process_action('handoff')
    true
  end

  def cleanup_streaming_message
    return unless @streaming_message

    # If streaming message still exists and has empty or streaming content, destroy it
    if @streaming_message.persisted?
      captain_logger.info('[Captain][ResponseBuilderJob] Cleaning up orphaned streaming message')
      destroy_streaming_message
    end
    @streaming_message = nil
    stop_typing_indicator
  rescue StandardError => e
    captain_logger.warn("[Captain][ResponseBuilderJob] cleanup_streaming_message failed: #{e.message}")
  end

  def destroy_streaming_message
    return unless @streaming_message&.persisted?

    # First mark as deleted to trigger MESSAGE_UPDATED event for frontend
    # This ensures the frontend removes the "Thinking..." bubble
    @streaming_message.update!(
      content: '',
      content_attributes: (@streaming_message.content_attributes || {}).merge('deleted' => true, 'streaming' => false)
    )
    # Now actually destroy the record
    @streaming_message.destroy!
    @streaming_message = nil
  rescue StandardError => e
    captain_logger.warn("[Captain][ResponseBuilderJob] destroy_streaming_message failed: #{e.message}")
    # Fallback: try direct destroy if update failed
    begin
      @streaming_message&.destroy!
    rescue StandardError
      nil
    end
    @streaming_message = nil
  end

  def log_error(error)
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  def captain_logger
    Captain::Logger.logger
  end

  def captain_v2_enabled?
    v2_config = InstallationConfig.find_by(name: 'CAPTAIN_V2_ENABLED')
    return ActiveModel::Type::Boolean.new.cast(v2_config.value) if v2_config&.value.present?

    account.feature_enabled?('captain_integration_v2')
  end

  def streaming_enabled?
    streaming_config = InstallationConfig.find_by(name: 'CAPTAIN_STREAMING_ENABLED')
    streaming_config&.value.present? && ActiveModel::Type::Boolean.new.cast(streaming_config.value)
  end
end

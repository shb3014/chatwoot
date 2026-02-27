require 'openai'

class Captain::Copilot::ChatService < Llm::BaseOpenAiService
  include Captain::ChatHelper

  attr_reader :assistant, :account, :user, :copilot_thread, :previous_history, :messages

  def initialize(assistant, config)
    super(model_type: :copilot)

    @assistant = assistant
    @account = assistant.account
    @user = nil
    @copilot_thread = nil
    @previous_history = []
    @conversation = nil
    setup_user(config)
    setup_conversation(config)
    setup_message_history(config)
    register_tools
    @messages = build_messages(config)
  end

  def generate_response(input)
    @messages << { role: 'user', content: input } if input.present?

    captain_logger.info "[Copilot] Account locale: #{account_locale_code}, language: #{@account.locale_english_name}"
    captain_logger.info "[Copilot] Detected customer language: #{@detected_customer_language}"
    captain_logger.info "[Copilot] User input: #{input&.truncate(200)}"

    # Enable streaming so copilot responses are delivered in real time via ActionCable
    setup_streaming_callback

    response = request_chat_completion

    # Send the final streaming content to ensure completeness before the real message arrives
    broadcast_final_streaming_content(response)

    is_reply_suggestion = response.is_a?(Hash) && response['reply_suggestion'] && response['content'].present?

    if is_reply_suggestion
      captain_logger.info "[Copilot] reply_suggestion detected — detected_customer_lang=#{@detected_customer_language}, account_locale=#{account_locale_code}"
      captain_logger.info "[Copilot] Content preview: #{response['content'].truncate(300)}"

      source_count = response['sources']&.length || 0
      captain_logger.info "[Copilot] LLM cited #{source_count} sources" if source_count.positive?

      # PHASE 1: Persist immediately WITH content + sources but WITHOUT translation.
      # This broadcasts to the frontend so the agent sees the response right away.
      persisted_message = flush_assistant_message

      # PHASE 2: Translate in background, then UPDATE the persisted message.
      # The update triggers after_update_commit which broadcasts the updated message.
      if @detected_customer_language != account_locale_code && persisted_message
        captain_logger.info "[Copilot] Languages differ — translating to #{@account.locale_english_name}..."
        translation = translate_to_account_language(response['content'])
        if translation.present?
          captain_logger.info "[Copilot] Translation complete, updating message #{persisted_message.id}"
          persisted_message.update!(message: persisted_message.message.merge('translation' => translation))
          response['translation'] = translation
        end
      else
        captain_logger.info '[Copilot] Same language — skipping translation'
      end
    else
      # Non-reply-suggestion: just persist
      flush_assistant_message
    end

    Rails.logger.debug { "#{self.class.name} Assistant: #{@assistant.id}, Received response #{response}" }
    Rails.logger.info(
      "#{self.class.name} Assistant: #{@assistant.id}, Incrementing response usage for account #{@account.id}"
    )
    @account.increment_response_usage

    response
  end

  private

  def setup_user(config)
    @user = @account.users.find_by(id: config[:user_id]) if config[:user_id].present?
  end

  def setup_conversation(config)
    return unless config[:conversation_id].present?

    @conversation = @account.conversations.find_by(display_id: config[:conversation_id])
    @detected_customer_language = detect_customer_language
  end

  def build_messages(_config)
    messages= [system_message]
    messages << account_id_context
    messages += @previous_history if @previous_history.present?
    messages += current_viewing_history if @conversation.present?
    messages
  end

  def setup_message_history(config)
    Rails.logger.info(
      "#{self.class.name} Assistant: #{@assistant.id}, Previous History: #{config[:previous_history]&.length || 0}, Language: #{config[:language]}"
    )

    @copilot_thread = @account.copilot_threads.find_by(id: config[:copilot_thread_id]) if config[:copilot_thread_id].present?
    @previous_history = if @copilot_thread.present?
                          @copilot_thread.previous_history
                        else
                          config[:previous_history].presence || []
                        end
  end

  def register_tools
    @tool_registry = Captain::ToolRegistryService.new(@assistant, user: @user)
    @tool_registry.register_tool(Captain::Tools::SearchDocumentationService)
    @tool_registry.register_tool(Captain::Tools::Copilot::GetArticleService)
    @tool_registry.register_tool(Captain::Tools::Copilot::GetContactService)
    @tool_registry.register_tool(Captain::Tools::Copilot::GetConversationService)
    @tool_registry.register_tool(Captain::Tools::Copilot::SearchArticlesService)
    @tool_registry.register_tool(Captain::Tools::Copilot::SearchContactsService)
    @tool_registry.register_tool(Captain::Tools::Copilot::SearchConversationsService)
    @tool_registry.register_tool(Captain::Tools::Copilot::SearchLinearIssuesService)
  end

  def system_message
    {
      role: 'system',
      content: Captain::Llm::SystemPromptsService.copilot_response_generator(
        @assistant.config['product_name'],
        @tool_registry.tools_summary,
        @assistant.config
      )
    }
  end

  def account_id_context
    {
      role: 'system',
      content: "The current account id is #{@account.id}. The account is using #{@account.locale_english_name} as the language."
    }
  end

  def current_viewing_history
    conversation_id = @conversation.display_id
    contact_id = @conversation.contact_id

    Rails.logger.info("#{self.class.name} Assistant: #{@assistant.id}, Setting viewing history for conversation_id=#{conversation_id}")

    # Include recent conversation messages so the LLM has full context
    recent_messages = @conversation.messages
                                   .where(message_type: [:incoming, :outgoing])
                                   .where(private: false)
                                   .order(created_at: :desc)
                                   .limit(20)
                                   .reverse
    transcript = recent_messages.map do |m|
      sender = m.message_type == 'incoming' ? 'Customer' : 'Agent'
      "#{sender}: #{m.content&.truncate(500)}"
    end.join("\n")

    captain_logger.info "[Copilot] Conversation transcript (#{recent_messages.size} messages):\n#{transcript}"

    # Tell the LLM explicitly what language the customer writes in
    language_note = "The customer is writing in #{language_name(@detected_customer_language)}. " \
                    'When drafting a reply to the customer, you MUST write in this language.'

    [{
      role: 'system',
      content: <<~HISTORY.strip
        You are currently viewing the conversation with the following details:
        Conversation ID: #{conversation_id}
        Contact ID: #{contact_id}

        #{language_note}

        Recent conversation messages:
        #{transcript}
      HISTORY
    }]
  end

  # Returns the ISO 639-1 code for the account locale (e.g. "en", "zh", "de")
  def account_locale_code
    @account.locale&.split('_')&.first&.downcase || 'en'
  end

  # Detect the customer's language from their messages using Unicode script analysis.
  # Returns an ISO 639-1 code (e.g. "en", "zh", "ja", "ko", "ar", "ru").
  def detect_customer_language
    return account_locale_code unless @conversation

    # Get substantial customer messages (skip very short ones)
    customer_texts = @conversation.messages
                                  .where(message_type: :incoming)
                                  .pluck(:content)
                                  .compact
                                  .select { |t| t.length > 5 }
                                  .join(' ')

    return account_locale_code if customer_texts.blank?

    # Count characters by script
    cjk    = customer_texts.scan(/[\u4e00-\u9fff\u3400-\u4dbf]/).length
    kana   = customer_texts.scan(/[\u3040-\u309f\u30a0-\u30ff]/).length
    hangul = customer_texts.scan(/[\uac00-\ud7af]/).length
    arabic = customer_texts.scan(/[\u0600-\u06ff]/).length
    cyrillic = customer_texts.scan(/[\u0400-\u04ff]/).length
    latin  = customer_texts.scan(/[a-zA-Z]/).length

    scores = {
      'ja' => kana > 0 ? kana + cjk : 0, # Japanese uses kana + kanji
      'zh' => kana > 0 ? 0 : cjk,         # Chinese = CJK without kana
      'ko' => hangul,
      'ar' => arabic,
      'ru' => cyrillic,
      'en' => latin
    }

    detected = scores.max_by { |_, v| v }&.first || 'en'
    detected = 'en' if scores.values.all?(&:zero?)
    detected
  end

  # Convert an ISO 639-1 code to a human-readable language name
  def language_name(code)
    {
      'en' => 'English', 'zh' => 'Chinese', 'ja' => 'Japanese',
      'ko' => 'Korean', 'ar' => 'Arabic', 'ru' => 'Russian',
      'de' => 'German', 'fr' => 'French', 'es' => 'Spanish',
      'pt' => 'Portuguese', 'it' => 'Italian', 'nl' => 'Dutch'
    }[code] || code
  end

  def translate_to_account_language(content)
    account_language = @account.locale_english_name
    captain_logger.info "[Copilot] Translating reply to #{account_language}..."

    translate_messages = [
      {
        role: 'system',
        content: "You are a translator. Translate the following text to #{account_language}. " \
                 'Output ONLY the translated text, nothing else. Preserve all formatting (markdown, bold, lists, etc.).'
      },
      { role: 'user', content: content }
    ]

    accumulated_translation = +''
    translation_model = InstallationConfig.find_by(name: 'CAPTAIN_FAST_MODEL')&.value.presence || @model
    translation_parameters = {
      model: translation_model,
      messages: translate_messages,
      temperature: 0.2
    }
    translation_parameters[:enable_thinking] = false if qwen_model?(translation_model)
    translation_parameters[:thinking] = ark_thinking_param(false) if deepseek_v32_model?(translation_model) || kimi_model?(translation_model)

    last_translation_broadcast_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    translation_stream = if @user && @copilot_thread
                           proc do |chunk|
                             delta = chunk.dig('choices', 0, 'delta', 'content')
                             next if delta.blank?

                             accumulated_translation << delta
                             now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                             elapsed = now - last_translation_broadcast_at
                             if elapsed >= 0.1 || accumulated_translation.length <= 50
                               broadcast_translation_streaming(accumulated_translation)
                               last_translation_broadcast_at = now
                             end
                           end
                         end

    if translation_stream
      @client.chat(parameters: translation_parameters.merge(stream: translation_stream))
      translated = accumulated_translation.strip
      broadcast_translation_streaming(translated) if translated.present?
    else
      raw = @client.chat(parameters: translation_parameters)
      translated = raw.dig('choices', 0, 'message', 'content')&.strip
    end

    captain_logger.info "[Copilot] Translation result: #{translated&.truncate(200)}"
    translated
  rescue StandardError => e
    captain_logger.error "[Copilot] Translation error: #{e.message}"
    nil
  end

  def broadcast_translation_streaming(translation)
    return unless @user && @copilot_thread
    return if translation.blank?

    ActionCable.server.broadcast(
      @user.pubsub_token,
      {
        event: 'copilot.message.streaming',
        data: {
          account_id: @account.id,
          copilot_thread_id: @copilot_thread.id,
          translation: translation
        }
      }
    )
  end

  # Send the complete response content as a final streaming broadcast.
  # This ensures the UI shows the full text even if throttling skipped the last few tokens.
  def broadcast_final_streaming_content(response)
    return unless @user && @copilot_thread && @streaming_callback
    return unless response.is_a?(Hash) && response['content'].present?

    ActionCable.server.broadcast(
      @user.pubsub_token,
      {
        event: 'copilot.message.streaming',
        data: {
          account_id: @account.id,
          copilot_thread_id: @copilot_thread.id,
          content: response['content']
        }
      }
    )
  end

  # Set up ActionCable streaming callback so copilot responses stream to the frontend in real time.
  # Throttled to broadcast at most every 100ms to avoid flooding WebSocket with per-token updates.
  def setup_streaming_callback
    unless @user && @copilot_thread
      captain_logger.info '[Copilot][Streaming] Skipped — user or copilot_thread missing'
      return
    end

    thread_id = @copilot_thread.id
    user_token = @user.pubsub_token
    acct_id = @account.id
    last_broadcast_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    broadcast_count = 0

    captain_logger.info "[Copilot][Streaming] Enabled for thread=#{thread_id} user=#{@user.id}"

    accumulated_reasoning = +''
    @streaming_callback = proc do |accumulated_content, _delta, reasoning_content, _reasoning_delta|
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      elapsed = now - last_broadcast_at
      accumulated_reasoning = reasoning_content.to_s if reasoning_content.present?

      # Broadcast immediately for the first ~50 chars, then throttle to every 100ms
      if elapsed >= 0.1 || accumulated_content.length <= 50 || accumulated_reasoning.length <= 50
        broadcast_count += 1
        captain_logger.info "[Copilot][Streaming] Broadcast ##{broadcast_count} len=#{accumulated_content.length}" if broadcast_count <= 3

        ActionCable.server.broadcast(
          user_token,
          {
            event: 'copilot.message.streaming',
            data: {
              account_id: acct_id,
              copilot_thread_id: thread_id,
              content: accumulated_content,
              thinking: accumulated_reasoning
            }
          }
        )
        last_broadcast_at = now
      end
    end
  end

  # Override persist_message from ChatHelper.
  # Buffer the final assistant message so we can add translation before persisting + broadcasting.
  # Non-assistant messages (thinking, user) are persisted immediately.
  def persist_message(message, message_type = 'assistant')
    return if @copilot_thread.blank?

    if message_type == 'assistant'
      @buffered_assistant_message = { message: message, message_type: message_type }
    else
      @copilot_thread.copilot_messages.create!(
        message: message,
        message_type: message_type
      )
    end
  end

  # Persist and broadcast the buffered assistant message.
  # Returns the persisted CopilotMessage record (so callers can update it later, e.g. with translation).
  def flush_assistant_message
    return nil unless @buffered_assistant_message && @copilot_thread.present?

    record = @copilot_thread.copilot_messages.create!(
      message: @buffered_assistant_message[:message],
      message_type: @buffered_assistant_message[:message_type]
    )
    @buffered_assistant_message = nil
    record
  end
end

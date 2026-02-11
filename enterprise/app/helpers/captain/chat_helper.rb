module Captain::ChatHelper
  def captain_logger
    Captain::Logger.logger
  end

  def request_chat_completion
    @captain_request_depth = (@captain_request_depth || 0) + 1
    request_id = SecureRandom.hex(6)
    request_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    captain_logger.info "[Captain][request_chat_completion] start id=#{request_id} depth=#{@captain_request_depth} messages=#{@messages.length}"
    log_chat_completion_request

    # Initialize response validator if not already present
    # Strictness can be configured via assistant config or globally via InstallationConfig
    @response_validator ||= Captain::ResponseValidatorService.new(strictness: validation_strictness)

    # Clear validator at the start of a new user turn (not during recursive tool processing)
    if new_user_turn?
      captain_logger.info 'Starting new conversation turn - clearing previous documentation'
      @response_validator.clear
      # Set conversation context so validator knows if this is an ongoing conversation
      @response_validator.set_conversation_context(@messages)

      # Force search for continuation words in ongoing conversations
      # This is a safety mechanism because some models (like Qwen) ignore system prompt instructions
      captain_logger.debug "Checking should_force_search? - messages length: #{@messages.length}, last message: '#{@messages.last&.dig(:content) || @messages.last&.dig('content')}'"
      force_search_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      force_search_result = should_force_search?
      force_search_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - force_search_start) * 1000).round
      captain_logger.info "should_force_search?=#{force_search_result.inspect} in #{force_search_elapsed_ms}ms"
      if force_search_result
        classification_type = force_search_result.is_a?(String) ? force_search_result : 'continuation'
        captain_logger.warn '🔒 FORCED SEARCH: Enforcing documentation search in conversation'
        # Return the result from the forced search (which calls request_chat_completion recursively)
        return force_documentation_search(classification_type)
      else
        captain_logger.debug 'should_force_search? returned false - continuing normal flow'
      end
    end

    # Use the thinking setting resolved by BaseOpenAiService (model-type-aware with fallback)
    thinking_enabled = @thinking_enabled || false

    tools = @tool_registry&.registered_tools || []
    has_tools = tools.any?

    # Temperature: use assistant config, fallback to global config, then default to 1
    default_temp = InstallationConfig.find_by(name: 'CAPTAIN_DEFAULT_TEMPERATURE')&.value&.to_f || 1
    temperature = @assistant&.config&.[]('temperature')&.to_f || default_temp
    temperature = normalized_temperature(temperature, @model, purpose: :chat)

    parameters = {
      model: @model,
      messages: @messages,
      tools: tools,
      temperature: temperature
    }

    # Some OpenAI-compatible providers require tool_choice explicitly for tool calling.
    parameters[:tool_choice] = 'auto' if has_tools

    is_deepseek_v32 = deepseek_v32_model?(@model)
    is_qwen = qwen_model?(@model)

    # Disable thinking mode for models that don't support it reliably.
    effective_thinking_enabled = thinking_enabled && !kimi_model?(@model)
    captain_logger.info 'Thinking mode disabled for this model' if thinking_enabled && !effective_thinking_enabled

    # response_format: json_object is not supported by Ark DeepSeek-V3.2 (even when thinking is disabled).
    # Qwen models also don't work well with response_format when tools are present - they return JSON content
    # directly instead of using tool_calls mechanism.
    # So we only enforce response_format for models that support it properly.
    parameters[:response_format] = { type: 'json_object' } if !effective_thinking_enabled && !is_deepseek_v32 && !(is_qwen && has_tools)

    # Ark DeepSeek-V3.2 expects a thinking object: { type: "enabled" | "disabled" }.
    if is_deepseek_v32
      parameters[:thinking] = ark_thinking_param(thinking_enabled)
      Rails.logger.warn 'DeepSeek-V3.2: response_format is disabled; relying on prompt + parser fallback for JSON' if has_tools
    elsif kimi_model?(@model)
      # Some Kimi models enable thinking by default unless explicitly disabled.
      parameters[:thinking] = ark_thinking_param(false)
      captain_logger.info 'Kimi model detected - forcing thinking=disabled to avoid reasoning_content errors'
    elsif effective_thinking_enabled
      # Non-Ark providers typically accept boolean.
      parameters[:thinking] = true
      captain_logger.warn 'Thinking mode enabled - response format constraint removed, relying on prompt for JSON' if has_tools
    elsif is_qwen && has_tools
      captain_logger.info 'Qwen model detected with tools: response_format disabled to enable proper tool calling'
    end

    chat_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = if streaming_enabled?
                 stream_chat_completion(parameters)
               else
                 @client.chat(parameters: parameters)
               end
    chat_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - chat_start) * 1000).round
    captain_logger.info "Chat completion finished in #{chat_elapsed_ms}ms"

    result = handle_response(response)
    request_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - request_start) * 1000).round
    captain_logger.info "request_chat_completion total=#{request_elapsed_ms}ms id=#{request_id} depth=#{@captain_request_depth}"
    result
  rescue StandardError => e
    endpoint_url = instance_variable_get(:@custom_endpoint_full_path) ||
                   "#{@client.instance_variable_get(:@uri_base)}/v1/chat/completions"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@client.instance_variable_get(:@access_token)}"
    }

    captain_logger.warn '=' * 80
    captain_logger.warn "#{self.class.name} Assistant: #{@assistant.id}, Error in chat completion"
    captain_logger.warn "Error: #{e.class.name} - #{e.message}"
    captain_logger.warn "Request URL: #{endpoint_url}"
    captain_logger.warn "Headers: #{headers.to_json}"
    captain_logger.warn "Model: #{@model}"
    captain_logger.warn "Request Parameters: #{parameters.to_json}"
    captain_logger.warn "Backtrace: #{e.backtrace.first(10).join("\n")}"
    captain_logger.warn '=' * 80
    raise e
  ensure
    @captain_request_depth = (@captain_request_depth || 1) - 1
  end

  private

  def streaming_enabled?
    @streaming_callback.present?
  end

  def stream_chat_completion(parameters)
    content = +''
    tool_calls = {}
    message_role = nil
    finish_reason = nil

    @client.chat(
      parameters: parameters,
      stream: proc do |chunk|
        choice = chunk.dig('choices', 0) || {}
        delta = choice['delta'] || {}
        message_role ||= delta['role']

        if delta['content'].present?
          content << delta['content']
          @streaming_callback&.call(content, delta['content'])
        end

        if delta['tool_calls'].present?
          delta['tool_calls'].each do |tool_delta|
            index = tool_delta['index'] || 0
            entry = tool_calls[index] ||= {
              'id' => tool_delta['id'],
              'type' => tool_delta['type'] || 'function',
              'function' => { 'name' => nil, 'arguments' => '' }
            }
            entry['id'] ||= tool_delta['id']
            entry['type'] ||= tool_delta['type']
            if tool_delta['function']
              entry['function']['name'] ||= tool_delta['function']['name']
              entry['function']['arguments'] << tool_delta['function']['arguments'].to_s
            end
          end
        end

        finish_reason = choice['finish_reason'] if choice['finish_reason'].present?
      end
    )

    tool_calls_array = tool_calls.keys.sort.map { |index| tool_calls[index] }
    {
      'choices' => [{
        'message' => {
          'role' => message_role || 'assistant',
          'content' => content.presence,
          'tool_calls' => tool_calls_array.presence
        },
        'finish_reason' => finish_reason || (tool_calls_array.any? ? 'tool_calls' : 'stop')
      }]
    }
  end

  def deepseek_v32_model?(model_name)
    model = model_name.to_s
    model.match?(/deepseek[-_]?v3[-_]?2/i) || model.match?(/deepseek[-_]?v3\.2/i)
  end

  def qwen_model?(model_name)
    model = model_name.to_s
    model.match?(/qwen/i)
  end

  def kimi_model?(model_name)
    model = model_name.to_s
    model.match?(/kimi/i)
  end

  def normalized_temperature(value, model_name, purpose:)
    return value if value.nil?

    if kimi_model?(model_name)
      return 1.0 if purpose == :classification

      return 0.6
    end

    value
  end

  def ark_thinking_param(enabled)
    { type: enabled ? 'enabled' : 'disabled' }
  end

  def handle_response(response)
    message = response.dig('choices', 0, 'message')

    # Log reasoning content if present (from thinking mode)
    reasoning_content = message['reasoning_content']
    captain_logger.debug "Reasoning content (thinking mode): #{reasoning_content}" if reasoning_content.present?

    has_tool_calls = message['tool_calls'].present?
    content_length = message['content']&.length || 0
    captain_logger.info "[Response] tool_calls=#{has_tool_calls} content_length=#{content_length}"

    if message['tool_calls']
      process_tool_calls(message['tool_calls'])
    else
      content = message['content'].strip

      # Strip markdown code fences if present (some models like DeepSeek wrap JSON in ```json ... ```)
      content = content.gsub(/\A```json\n/, '').gsub(/\n```\z/, '')

      begin
        parsed_message = JSON.parse(content)

        # Validate response against captured tool results
        if @response_validator
          validation = @response_validator.validate_response(parsed_message['response'] || '')

          captain_logger.info "[Validation] valid=#{validation[:valid]} reject=#{validation[:should_reject]} reason=\"#{validation[:reason]}\""

          # If validation determines response should be rejected, force a safe response
          if validation[:should_reject]
            captain_logger.warn "VALIDATION REJECTED: #{validation[:reason]}"

            # Force a safe response using i18n
            parsed_message = {
              'reasoning' => 'Response validation detected potential issues. Unable to provide accurate information from documentation.',
              'response' => I18n.t('captain.assistant.no_answer_fallback')
            }
          elsif !validation[:valid]
            # Log warning but allow response (based on strictness setting)
            captain_logger.warn "VALIDATION WARNING: #{validation[:reason]} (allowed due to strictness setting)"
          end
        end

        parsed_message = append_referenced_articles(parsed_message)
        persist_message(parsed_message, 'assistant')
        parsed_message
      rescue JSON::ParserError => e
        captain_logger.warn "Failed to parse response as JSON: #{e.message}"
        captain_logger.warn "Response content: #{content}"

        # Fallback: wrap plain text response in expected JSON structure
        fallback_message = {
          'reasoning' => reasoning_content || 'Model returned non-JSON response',
          'response' => content
        }
        captain_logger.warn "Using fallback JSON structure: #{fallback_message.to_json}"

        # Validate the fallback response too
        if @response_validator
          validation = @response_validator.validate_response(fallback_message['response'] || '')

          captain_logger.info '=' * 80
          captain_logger.info 'Response Validation (Fallback):'
          captain_logger.info "Valid: #{validation[:valid]}"
          captain_logger.info "Reason: #{validation[:reason]}"
          captain_logger.info "Confidence: #{validation[:confidence]}"
          captain_logger.info "Should Reject: #{validation[:should_reject]}"
          captain_logger.info "Strictness: #{@response_validator.instance_variable_get(:@strictness)}"
          captain_logger.info "Documentation content available: #{@response_validator.get_documentation_content.length} chars"
          captain_logger.info "Indicators: #{validation[:indicators]&.join(', ') || 'none'}" if validation[:indicators]
          captain_logger.info '=' * 80

          # If validation determines response should be rejected, force a safe response
          if validation[:should_reject]
            captain_logger.warn "VALIDATION REJECTED (Fallback): #{validation[:reason]}"
            captain_logger.warn "Original response: #{fallback_message['response']}"

            # Force a safe response using i18n
            fallback_message = {
              'reasoning' => 'Response validation detected potential issues. Unable to provide accurate information from documentation.',
              'response' => I18n.t('captain.assistant.no_answer_fallback')
            }
          elsif !validation[:valid]
            # Log warning but allow response (based on strictness setting)
            captain_logger.warn "VALIDATION WARNING (Fallback): #{validation[:reason]} (allowed due to strictness setting)"
          end
        end

        fallback_message = append_referenced_articles(fallback_message)
        persist_message(fallback_message, 'assistant')
        fallback_message
      end
    end
  end

  def process_tool_calls(tool_calls)
    tool_calls_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    append_tool_calls(tool_calls)
    tool_calls.each do |tool_call|
      process_tool_call(tool_call)
    end
    tool_calls_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - tool_calls_start) * 1000).round
    captain_logger.info "Processed #{tool_calls.length} tool call(s) in #{tool_calls_elapsed_ms}ms"
    request_chat_completion
  end

  def process_tool_call(tool_call)
    arguments = JSON.parse(tool_call['function']['arguments'])
    function_name = tool_call['function']['name']
    tool_call_id = tool_call['id']

    if @tool_registry.respond_to?(function_name)
      execute_tool(function_name, arguments, tool_call_id)
    else
      process_invalid_tool_call(function_name, tool_call_id)
    end
  end

  def execute_tool(function_name, arguments, tool_call_id)
    tool_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    persist_message(
      {
        content: I18n.t('captain.copilot.using_tool', function_name: function_name),
        function_name: function_name
      },
      'assistant_thinking'
    )
    result = @tool_registry.send(function_name, arguments)
    tool_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - tool_start) * 1000).round
    captain_logger.info "Tool #{function_name} completed in #{tool_elapsed_ms}ms"

    # Capture tool result for validation
    @response_validator ||= Captain::ResponseValidatorService.new
    @response_validator.capture_tool_result(function_name, result)

    persist_message(
      {
        content: I18n.t('captain.copilot.completed_tool_call', function_name: function_name),
        function_name: function_name
      },
      'assistant_thinking'
    )
    append_tool_response(result, tool_call_id)
  end

  def append_tool_calls(tool_calls)
    @messages << {
      role: 'assistant',
      tool_calls: tool_calls
    }
  end

  def process_invalid_tool_call(function_name, tool_call_id)
    persist_message({ content: I18n.t('captain.copilot.invalid_tool_call'), function_name: function_name }, 'assistant_thinking')
    append_tool_response(I18n.t('captain.copilot.tool_not_available'), tool_call_id)
  end

  def append_tool_response(content, tool_call_id)
    @messages << {
      role: 'tool',
      tool_call_id: tool_call_id,
      content: content
    }
  end

  def append_referenced_articles(parsed_message)
    references = extract_referenced_articles
    return parsed_message if references.empty?

    content_key = if parsed_message.key?('response')
                    'response'
                  elsif parsed_message.key?('content')
                    'content'
                  end
    return parsed_message unless content_key

    content = parsed_message[content_key].to_s
    unless should_include_references?(content)
      parsed_message[content_key] = strip_plain_citations(strip_inline_citations(content))
      return parsed_message
    end

    # Strip any markdown link citations like [[1](url)], but keep simple [1] markers for conversion
    content = strip_inline_citations(content)
    parsed_message[content_key] = append_reference_list(content, filter_references_by_locale(references))
    parsed_message
  end

  def extract_referenced_articles
    return [] unless @response_validator

    tool_results = @response_validator.tool_results.select { |result| result[:tool] == 'search_documentation' }
    references = tool_results.flat_map { |result| parse_referenced_articles_from_text(result[:content]) }

    # Deduplicate by URL (preferred) then title
    seen = {}
    references.select do |ref|
      key = ref[:url].presence || ref[:title]
      next false if key.blank? || seen[key]

      seen[key] = true
      true
    end
  end

  def parse_referenced_articles_from_text(text)
    return [] if text.blank?

    references = []

    if text.match?(/\*\*(?:Sources|Referenced Articles)\*\*:?/i)
      section = text.split(/\*\*(?:Sources|Referenced Articles)\*\*:?/i, 2).last
      section.to_s.lines.each do |line|
        stripped = line.strip
        next unless stripped.match?(/^\[\d+\]\s+/)

        match = stripped.match(%r{^\[\d+\]\s+(?:\[(.+?)\]\((https?://\S+)\)|(.+?)\s+-\s+(https?://\S+))(?:\s+\(locale:\s*([^)]+)\))?(?:\s+\(type:\s*([^)]+)\))?})
        next unless match

        title = match[1].presence || match[3].to_s
        url = match[2].presence || match[4].to_s
        locale = match[5].to_s.strip.presence
        ref_type = match[6].to_s.strip.presence || 'article'
        references << {
          title: title.strip,
          locale: locale,
          url: url.strip,
          type: ref_type
        }
      end
    end

    # Fallback: parse article/source blocks when reference list is missing
    if references.empty?
      current_title = nil
      current_block_type = 'article'
      text.lines.each do |line|
        stripped = line.strip
        if stripped.start_with?('Article Title:')
          current_title = stripped.sub('Article Title:', '').strip
          current_block_type = 'article'
        elsif stripped.start_with?('Source Title:')
          current_title = stripped.sub('Source Title:', '').strip
          # Will be refined when we see "Source URL:" below
          current_block_type = 'article'
        elsif stripped.start_with?('Source URL:')
          url = stripped.sub('Source URL:', '').strip
          if url.present? && current_title.present?
            references << { title: current_title, url: url, locale: nil, type: 'web_url' }
            current_title = nil
          end
        elsif stripped.start_with?('Source:')
          url = stripped.split(':', 2).last&.strip
          url = url.gsub(%r{\A\[(.+?)\]\((https?://\S+)\)\z}, '\2')
          if url.present? && current_title.present?
            references << { title: current_title, url: url, locale: nil, type: current_block_type }
            current_title = nil
          end
        elsif stripped.match?(%r{\A\[(.+?)\]\((https?://\S+)\)\s*\z})
          match = stripped.match(%r{\A\[(.+?)\]\((https?://\S+)\)\s*\z})
          if match
            references << { title: match[1].strip, url: match[2].strip, locale: nil, type: 'article' }
            current_title = nil
          end
        end
      end
    end

    references
  end

  def strip_inline_citations(content)
    content
      .gsub(/\s*\[\[\d+\]\([^)]+\)\]/, '')
  end

  def strip_plain_citations(content)
    content.gsub(/\s*\[(\d+)\]/, '')
  end

  def convert_inline_citations(content, references)
    return content if references.empty?

    # Build a lookup of citation chips by index
    citation_chips = {}
    references.each_with_index do |reference, index|
      ref_num = index + 1
      title_escaped = CGI.escapeHTML(reference[:title].to_s)
      url_escaped = CGI.escapeHTML(reference[:url].to_s)
      ref_type = CGI.escapeHTML(reference[:type] || 'article')
      citation_chips[ref_num] =
        "<cite class=\"citation-chip\" data-ref=\"#{ref_num}\" data-title=\"#{title_escaped}\" data-url=\"#{url_escaped}\" data-type=\"#{ref_type}\">#{ref_num}</cite>"
    end

    # Replace [1], [2], etc. with citation chips, or remove if no matching reference
    # This handles citations for learned conversations (which shouldn't have citations)
    content.gsub(/\s*\[(\d+)\]/) do |_match|
      ref_num = ::Regexp.last_match(1).to_i
      citation_chips[ref_num] || '' # Remove citations without matching references
    end
  end

  def normalize_inline_citations(content, references)
    ref_order = content.scan(/\[(\d+)\]/).flatten.map(&:to_i).uniq
    ref_order = ref_order.select { |ref| references[ref - 1].present? }

    ref_mapping = {}
    normalized_references = []
    ref_order.each_with_index do |old_ref, index|
      new_ref = index + 1
      ref_mapping[old_ref] = new_ref
      normalized_references << references[old_ref - 1]
    end

    seen = {}
    cleaned_content = content.gsub(/\s*\[(\d+)\]/) do
      ref_num = ::Regexp.last_match(1).to_i
      next '' if seen[ref_num]

      seen[ref_num] = true
      new_ref = ref_mapping[ref_num]
      new_ref ? "[#{new_ref}]" : ''
    end.rstrip

    # Ensure citations appear after sentence-ending punctuation.
    cleaned_content = cleaned_content.gsub(/(\[\d+\])([.!?])/, '\2\1')
    # If punctuation is between adjacent citations, move it after the last citation.
    3.times do
      cleaned_content = cleaned_content.gsub(/(\[\d+\])\.\s*(\[\d+\])/, '\1\2.')
    end

    [cleaned_content, normalized_references]
  end

  def remove_reference_section(content)
    lines = content.lines
    cleaned = []
    skipping = false

    lines.each do |line|
      if line.match?(/\A\**\s*(?:referenced articles|sources?)\s*\**:?/i)
        skipping = true
        next
      end

      if skipping
        next if line.strip.empty? || line.strip == '---' || line.strip.match?(/^\d+\.\s+/)
        next if line.strip.match?(/^\[\d+\]\s+/)

        skipping = false
      end

      next if line.strip.match?(/\A\**\s*source\s*:\s*/i)

      cleaned << line unless skipping
    end

    cleaned.join
  end

  def append_reference_list(content, references)
    return content.rstrip if references.empty?

    # Normalize inline citations to paragraph-end before conversion
    processed_content, normalized_references = normalize_inline_citations(content, references)

    # Convert inline [1], [2] markers to citation chips
    processed_content = convert_inline_citations(processed_content, normalized_references)

    # Remove any Source/Sources section at the end (since we will re-append)
    processed_content = remove_reference_section(processed_content)

    return processed_content.rstrip if normalized_references.empty?

    citation_chips = normalized_references.map.with_index do |reference, index|
      ref_num = index + 1
      title_escaped = CGI.escapeHTML(reference[:title].to_s)
      url_escaped = CGI.escapeHTML(reference[:url].to_s)
      ref_type = CGI.escapeHTML(reference[:type] || 'article')
      "<cite class=\"citation-chip\" data-ref=\"#{ref_num}\" data-title=\"#{title_escaped}\" data-url=\"#{url_escaped}\" data-type=\"#{ref_type}\">#{ref_num}</cite>"
    end

    "#{processed_content.rstrip}\n\n**Sources:** #{citation_chips.join(' ')}"
  end

  def should_include_references?(content)
    return true if content.match?(/\[\d+\]/)

    fallback_phrases = [
      "i couldn't find",
      "i don't have that information",
      "i apologize, but i couldn't find reliable information",
      'unable to provide accurate information'
    ]
    fallback_phrases.none? { |phrase| content.downcase.include?(phrase) }
  end

  def filter_references_by_locale(references)
    locale = detect_conversation_locale
    return references if locale.blank?

    language = locale.to_s.split(/[-_]/).first
    return references if language.blank?

    references.select do |reference|
      ref_locale = reference[:locale].to_s.split(/[-_]/).first
      ref_locale.blank? || ref_locale == language
    end
  end

  def detect_conversation_locale
    return nil unless @conversation

    locale = @conversation.custom_attributes['locale']
    locale ||= @conversation.additional_attributes['browser_language']
    locale ||= @conversation.contact&.additional_attributes&.dig('browser_language')
    locale.to_s.split(/[-_]/).first.presence
  end

  def log_chat_completion_request
    # Simplified logging - avoid dumping full messages which can be huge
    captain_logger.info "[ChatCompletion] assistant=#{@assistant.id} model=#{@model} messages=#{@messages.length} tools=#{@tool_registry&.registered_tools&.length || 0}"
  end

  # Check if we should force a documentation search
  # This happens when:
  # 1. We're in an ongoing conversation (not the first message)
  # 2. The user sent a continuation signal (yes, ok, done, next, etc.)
  # 3. The search_documentation tool is available
  # 4. The assistant didn't just offer a handoff (to avoid interfering with handoff flow)
  def should_force_search?
    # Skip if we're already in a forced search context (prevents infinite loop)
    return false if @skip_forced_search

    return false unless @messages.length > 2 # Need at least: system, user, assistant, user
    return false unless @tool_registry&.respond_to?(:search_documentation)

    # Use the last user message, even if system context was appended after it
    last_user_message = last_user_message_content
    return false if last_user_message.nil? || last_user_message.strip.empty?

    if first_user_message?
      # Skip classifier on first user message to avoid extra call
      # Return 'new_question' if it's a real question, false if it's just a greeting
      return greeting_only?(last_user_message) ? false : 'new_question'
    end

    # Use LLM to intelligently classify the user's message
    classification = classify_user_message_intent(last_user_message)

    case classification
    when 'handoff_confirmation'
      # User is confirming a handoff request (e.g., "yes" after "Would you like to speak with an agent?")
      captain_logger.info 'LLM classified as handoff confirmation - skipping forced search'
      false
    when 'clarification_needed'
      # User said "yes" to an offer with multiple options - need to ask which one
      captain_logger.info 'LLM classified as clarification_needed - will ask user to specify'
      classification
    when 'continuation', 'new_question'
      # In ongoing conversations we always search, regardless of continuation vs new question
      # Return the classification type so force_documentation_search knows which query to use
      captain_logger.info "LLM classified as #{classification} - forcing search in ongoing conversation"
      classification
    else
      # Fallback: use simple pattern matching if LLM classification fails
      captain_logger.warn 'LLM classification failed, falling back to pattern matching'
      fallback_should_force_search(last_user_message)
    end
  rescue StandardError => e
    captain_logger.error "Error in should_force_search?: #{e.message}, falling back to pattern matching"
    fallback_should_force_search(last_user_message&.strip&.downcase)
  end

  # Use LLM to classify user message intent based on conversation context
  def classify_user_message_intent(user_message)
    # Get last assistant message for context
    last_assistant_msg = @messages.reverse.find do |m|
      role = m[:role] || m['role']
      role == 'assistant'
    end

    assistant_content = extract_message_content(last_assistant_msg)

    # Create a lightweight classification prompt
    classification_prompt = <<~PROMPT
      You are a conversation analyzer. Classify the user's response based on context.

      Assistant's last message: "#{assistant_content}"
      User's response: "#{user_message}"

      Classify the user's response as ONE of:
      - "handoff_confirmation": User confirming they want to speak with a human agent (only if assistant explicitly offered to transfer to human/agent)
      - "clarification_needed": User said "yes" to an offer with MULTIPLE DISTINCT options presented (e.g., "help with X or Y?", a bulleted list of choices)
      - "continuation": User wants to proceed with a SINGLE offered action, OR user completed a step (e.g., "done", "yes please", "I tried that")
      - "new_question": User asking a new question or providing new information

      CRITICAL RULES:
      1. If assistant offered ONE thing (e.g., "Would you like step-by-step guidance?") and user says "yes" → "continuation"
      2. If assistant offered MULTIPLE choices (e.g., "X or Y?" or a list of options) and user says "yes" → "clarification_needed"
      3. "clarification_needed" is ONLY for when you cannot determine which of multiple options the user wants

      Respond with ONLY the classification keyword, nothing else.
    PROMPT

    # Use a lightweight, fast model for classification
    classification_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    classification_response = @client.chat(
      parameters: {
        model: classification_model,
        messages: [
          { role: 'system', content: 'You are a precise classifier. Respond with only the classification keyword.' },
          { role: 'user', content: classification_prompt }
        ],
        temperature: normalized_temperature(0.0, classification_model, purpose: :classification),
        max_tokens: 10
      }
    )
    classification_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - classification_start) * 1000).round

    result = classification_response.dig('choices', 0, 'message', 'content')&.strip&.downcase
    captain_logger.info "LLM classification result: #{result} in #{classification_elapsed_ms}ms"

    # Validate result is one of expected values
    %w[continuation handoff_confirmation new_question clarification_needed].include?(result) ? result : nil
  rescue StandardError => e
    captain_logger.warn "LLM classification error: #{e.message}"
    nil
  end

  # Fallback pattern matching if LLM classification fails
  def fallback_should_force_search(last_user_message)
    return false if last_user_message.nil?

    continuation_signals = [
      'yes', 'yep', 'yeah', 'yup', 'ok', 'okay', 'sure',
      'done', 'finished', 'completed', 'ready',
      'next', 'continue', 'go on', 'proceed',
      'i did', "i've done", 'all set'
    ]

    is_continuation = continuation_signals.any? do |signal|
      last_user_message == signal || last_user_message.start_with?(signal)
    end

    if is_continuation
      # Check if assistant offered handoff using fallback pattern matching
      if fallback_assistant_offered_handoff?
        captain_logger.info 'Fallback: detected handoff offer - skipping forced search'
        return false
      end

      captain_logger.info 'Fallback: detected continuation signal'
      return 'continuation'
    end

    # If it's not a continuation signal, it might be a new question
    # Return 'new_question' if the message is substantive (not a greeting)
    return 'new_question' unless greeting_only?(last_user_message)

    false
  end

  # Fallback pattern matching for handoff detection
  def fallback_assistant_offered_handoff?
    last_assistant_msg = @messages.reverse.find do |m|
      role = m[:role] || m['role']
      role == 'assistant'
    end

    return false unless last_assistant_msg

    content = extract_message_content(last_assistant_msg)
    return false unless content.is_a?(String)

    handoff_patterns = [
      'would you like to speak with',
      'speak with a support agent',
      'talk to a human'
    ]

    content_lower = content.downcase
    handoff_patterns.any? { |pattern| content_lower.include?(pattern) }
  end

  # Extract message content, handling both plain text and JSON format
  def extract_message_content(message)
    return nil unless message

    content = message[:content] || message['content']
    return nil unless content

    # Handle JSON-formatted content ({"reasoning": "...", "response": "..."})
    if content.is_a?(String) && content.strip.start_with?('{')
      begin
        parsed = JSON.parse(content)
        content = parsed['response'] || parsed[:response] || content
      rescue JSON::ParserError
        # Not JSON, use as-is
      end
    end

    content
  end

  def new_user_turn?
    last_user_index = @messages.rindex { |message| message_role(message) == 'user' }
    return false unless last_user_index

    last_assistant_index = @messages.rindex { |message| message_role(message) == 'assistant' }
    last_tool_index = @messages.rindex { |message| message_role(message) == 'tool' }
    last_response_index = [last_assistant_index, last_tool_index].compact.max

    # If the most recent non-system response was before the last user message,
    # this is a new user turn (even if system context was appended after it).
    last_response_index.nil? || last_user_index > last_response_index
  end

  def last_user_message_content
    message = @messages.reverse.find { |entry| message_role(entry) == 'user' }
    message&.dig(:content) || message&.dig('content')
  end

  def message_role(message)
    message&.dig(:role) || message&.dig('role')
  end

  def first_user_message?
    user_messages = @messages.count { |message| message_role(message) == 'user' }
    assistant_messages = @messages.count { |message| message_role(message) == 'assistant' }
    user_messages == 1 && assistant_messages.zero?
  end

  def greeting_only?(message)
    normalized = message.to_s.strip.downcase
    normalized.match?(/\A(?:hi|hello|hey|thanks|thank you|bye|goodbye)[!. ]*\z/)
  end

  def validation_strictness
    @assistant&.config&.[]('validation_strictness')&.to_sym ||
      InstallationConfig.find_by(name: 'CAPTAIN_VALIDATION_STRICTNESS')&.value&.to_sym ||
      :moderate
  end

  # Determine which model to use for classification
  # Priority: classification-specific config > fast model config > current model
  def classification_model
    # Check for classification-specific model config
    classification_model_config = InstallationConfig.find_by(name: 'CAPTAIN_CLASSIFICATION_MODEL')
    return classification_model_config.value if classification_model_config&.value.present?

    # Fall back to fast model if configured (classification is a lightweight task)
    fast_model = InstallationConfig.find_by(name: 'CAPTAIN_FAST_MODEL')&.value
    return fast_model if fast_model.present?

    # Fall back to current model
    @model
  end

  # Extract what topic to search for when user confirms a continuation (e.g., "yes", "ok")
  # This looks at the assistant's last offer and extracts a relevant search query
  def extract_continuation_search_query
    # Get the assistant's last message to see what they offered
    last_assistant_msg = @messages.reverse.find do |m|
      role = m[:role] || m['role']
      role == 'assistant'
    end

    assistant_content = extract_message_content(last_assistant_msg)

    # If no assistant message or content, fall back to original problem
    return fallback_to_original_problem unless assistant_content.present?

    # Use LLM to extract the follow-up topic from the assistant's offer
    extraction_prompt = <<~PROMPT
      The assistant just said: "#{assistant_content.slice(0, 500)}"

      The user responded with a confirmation like "yes", "ok", "sure", etc.

      Extract what topic the user is confirming they want help with. Return ONLY a concise search query (5-10 words) that would find relevant documentation for that topic.

      For example:
      - If assistant offered "Would you like step-by-step guidance on updating it?" -> "how to update firmware step by step"
      - If assistant offered "Would you like help connecting to Wi-Fi?" -> "how to connect to Wi-Fi setup guide"

      Return ONLY the search query, nothing else.
    PROMPT

    begin
      extraction_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      extraction_response = @client.chat(
        parameters: {
          model: classification_model,
          messages: [
            { role: 'system', content: 'You extract search queries from conversation context. Return only the search query.' },
            { role: 'user', content: extraction_prompt }
          ],
          temperature: normalized_temperature(0.0, classification_model, purpose: :classification),
          max_tokens: 50
        }
      )
      extraction_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - extraction_start) * 1000).round

      extracted_query = extraction_response.dig('choices', 0, 'message', 'content')&.strip
      captain_logger.info "Extracted continuation query: '#{extracted_query}' in #{extraction_elapsed_ms}ms"

      # Validate the extracted query is reasonable
      return extracted_query if extracted_query.present? && extracted_query.length > 5 && extracted_query.length < 200

      captain_logger.warn 'Extracted query invalid, falling back to original problem'
      fallback_to_original_problem
    rescue StandardError => e
      captain_logger.warn "Failed to extract continuation query: #{e.message}, falling back"
      fallback_to_original_problem
    end
  end

  def fallback_to_original_problem
    user_messages = @messages.select { |m| (m[:role] || m['role']) == 'user' }
    original_problem = user_messages.find { |m| (m[:content] || m['content']).to_s.length > 20 }&.then { |msg| msg[:content] || msg['content'] }

    if original_problem.present?
      captain_logger.info 'Falling back to original problem for search'
      original_problem
    else
      recent_context = @messages.last(5)
                                .select { |m| (m[:role] || m['role']) == 'user' || (m[:role] || m['role']) == 'assistant' }
                                .map { |m| m[:content] || m['content'] }
                                .join(' ')
      captain_logger.info 'Falling back to recent context for search'
      recent_context.slice(0, 200)
    end
  end

  # Force a documentation search with context from the conversation
  # @param classification [String] 'new_question', 'continuation', or 'clarification_needed'
  def force_documentation_search(classification = 'continuation')
    # Get the current user message (the one we're responding to)
    current_user_message = last_user_message_content

    # For clarification_needed, don't search - just add context for the LLM to ask which option
    if classification == 'clarification_needed'
      captain_logger.info 'Clarification needed - adding context to ask user which option they want'
      @messages << {
        role: 'system',
        content: 'IMPORTANT: The user said "yes" but your previous message offered multiple options. Do NOT repeat your previous response. Ask the user to specify which option they need help with. Be brief and direct.'
      }
      # Set flag to skip forced search on recursive call (prevent infinite loop)
      @skip_forced_search = true
      begin
        return request_chat_completion
      ensure
        @skip_forced_search = false
      end
    end

    # For new questions, always use the current message as the search query
    # For continuations (yes, done, ok, next), extract what the user is confirming from the assistant's offer
    if classification == 'new_question' && current_user_message.present? && current_user_message.length > 3
      search_query = current_user_message
      captain_logger.info 'Using current user message for new_question search'
    else
      # For continuations, extract the topic from the assistant's last offer/question
      search_query = extract_continuation_search_query
      captain_logger.info "Using extracted continuation topic for search: #{search_query}"
    end

    captain_logger.info "Force searching with query: #{search_query}"

    # Execute the search
    return unless @tool_registry.respond_to?(:search_documentation)

    result = @tool_registry.search_documentation({ 'search_query' => search_query })

    # Capture result for validation
    @response_validator ||= Captain::ResponseValidatorService.new
    @response_validator.capture_tool_result('search_documentation', result)

    captain_logger.info "Forced search returned #{result.length} chars of documentation"

    # Append tool call and response to messages (so model knows we searched)
    # Use symbol keys to match the rest of the message structure
    tool_call_id = "forced_#{SecureRandom.hex(8)}"

    @messages << {
      role: 'assistant',
      content: nil,
      tool_calls: [{
        'id' => tool_call_id,
        'type' => 'function',
        'function' => {
          'name' => 'search_documentation',
          'arguments' => { 'search_query' => search_query }.to_json
        }
      }]
    }

    @messages << {
      role: 'tool',
      tool_call_id: tool_call_id,
      content: result
    }

    # Now request chat completion with the search results in context and return the result
    return request_chat_completion
  end
end

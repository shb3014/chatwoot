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
    strictness = @assistant&.config&.[]('validation_strictness')&.to_sym ||
                 InstallationConfig.find_by(name: 'CAPTAIN_VALIDATION_STRICTNESS')&.value&.to_sym ||
                 :moderate
    @response_validator ||= Captain::ResponseValidatorService.new(strictness: strictness)

    # Clear validator at the start of a new user turn (not during recursive tool processing)
    # We detect a new turn by checking if the last message is from the user
    last_message_role = @messages.last&.dig(:role) || @messages.last&.dig('role')
    if last_message_role == 'user'
      captain_logger.info 'Starting new conversation turn - clearing previous documentation'
      @response_validator.clear
      # Set conversation context so validator knows if this is an ongoing conversation
      @response_validator.set_conversation_context(@messages)

      # Force search for continuation words in ongoing conversations
      # This is a safety mechanism because some models (like Qwen) ignore system prompt instructions
      captain_logger.debug "Checking should_force_search? - messages length: #{@messages.length}, last message: '#{@messages.last&.dig(:content) || @messages.last&.dig('content')}'"
      force_search_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      should_force = should_force_search?
      force_search_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - force_search_start) * 1000).round
      captain_logger.info "should_force_search?=#{should_force} in #{force_search_elapsed_ms}ms"
      if should_force
        captain_logger.warn '🔒 FORCED SEARCH: Detected continuation signal in ongoing conversation'
        # Return the result from the forced search (which calls request_chat_completion recursively)
        return force_documentation_search
      else
        captain_logger.debug 'should_force_search? returned false - continuing normal flow'
      end
    end

    # Check if thinking mode is enabled (for models like DeepSeek-v3.2)
    thinking_config = InstallationConfig.find_by(name: 'CAPTAIN_THINKING_ENABLED')
    thinking_enabled = thinking_config&.value.present? && ActiveModel::Type::Boolean.new.cast(thinking_config.value)

    tools = @tool_registry&.registered_tools || []
    has_tools = tools.any?

    # Temperature: use assistant config, fallback to global config, then default to 1
    default_temp = InstallationConfig.find_by(name: 'CAPTAIN_DEFAULT_TEMPERATURE')&.value&.to_f || 1
    temperature = @assistant&.config&.[]('temperature')&.to_f || default_temp

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

    # response_format: json_object is not supported by Ark DeepSeek-V3.2 (even when thinking is disabled).
    # Qwen models also don't work well with response_format when tools are present - they return JSON content
    # directly instead of using tool_calls mechanism.
    # So we only enforce response_format for models that support it properly.
    parameters[:response_format] = { type: 'json_object' } if !thinking_enabled && !is_deepseek_v32 && !is_qwen

    # Ark DeepSeek-V3.2 expects a thinking object: { type: "enabled" | "disabled" }.
    if is_deepseek_v32
      parameters[:thinking] = ark_thinking_param(thinking_enabled)
      Rails.logger.warn 'DeepSeek-V3.2: response_format is disabled; relying on prompt + parser fallback for JSON' if has_tools
    elsif thinking_enabled
      # Non-Ark providers typically accept boolean.
      parameters[:thinking] = true
      captain_logger.warn 'Thinking mode enabled - response format constraint removed, relying on prompt for JSON' if has_tools
    elsif is_qwen && has_tools
      captain_logger.info 'Qwen model detected with tools: response_format disabled to enable proper tool calling'
    end

    chat_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = @client.chat(parameters: parameters)
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

  def deepseek_v32_model?(model_name)
    model = model_name.to_s
    model.match?(/deepseek[-_]?v3[-_]?2/i) || model.match?(/deepseek[-_]?v3\.2/i)
  end

  def qwen_model?(model_name)
    model = model_name.to_s
    model.match?(/qwen/i)
  end

  def ark_thinking_param(enabled)
    { type: enabled ? 'enabled' : 'disabled' }
  end

  def handle_response(response)
    captain_logger.info '=' * 80
    captain_logger.info "#{self.class.name} Assistant: #{@assistant.id} - Handling Response"
    captain_logger.info "Full response: #{response.to_json}"

    message = response.dig('choices', 0, 'message')

    # Log reasoning content if present (from thinking mode)
    reasoning_content = message['reasoning_content']
    captain_logger.info "Reasoning content (thinking mode): #{reasoning_content}" if reasoning_content.present?

    captain_logger.info "Message extracted: #{message.to_json}"
    captain_logger.info "Tool calls present: #{message['tool_calls'].present?}"
    captain_logger.info "Tool calls content: #{message['tool_calls'].to_json}" if message['tool_calls']
    captain_logger.info '=' * 80

    if message['tool_calls']
      captain_logger.info 'Processing tool calls...'
      process_tool_calls(message['tool_calls'])
    else
      captain_logger.info 'No tool calls, parsing message content as JSON...'
      content = message['content'].strip

      # Strip markdown code fences if present (some models like DeepSeek wrap JSON in ```json ... ```)
      content = content.gsub(/\A```json\n/, '').gsub(/\n```\z/, '')

      begin
        parsed_message = JSON.parse(content)

        # Validate response against captured tool results
        if @response_validator
          validation = @response_validator.validate_response(parsed_message['response'] || '')

          captain_logger.info '=' * 80
          captain_logger.info 'Response Validation:'
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
            captain_logger.warn "VALIDATION REJECTED: #{validation[:reason]}"
            captain_logger.warn "Original response: #{parsed_message['response']}"

            # Force a safe response
            parsed_message = {
              'reasoning' => 'Response validation detected potential issues. Unable to provide accurate information from documentation.',
              'response' => "I apologize, but I couldn't find reliable information about that in our documentation. Would you like to speak with a support agent who can help you better?"
            }
          elsif !validation[:valid]
            # Log warning but allow response (based on strictness setting)
            captain_logger.warn "VALIDATION WARNING: #{validation[:reason]} (allowed due to strictness setting)"
          end
        end

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

            # Force a safe response
            fallback_message = {
              'reasoning' => 'Response validation detected potential issues. Unable to provide accurate information from documentation.',
              'response' => "I apologize, but I couldn't find reliable information about that in our documentation. Would you like to speak with a support agent who can help you better?"
            }
          elsif !validation[:valid]
            # Log warning but allow response (based on strictness setting)
            captain_logger.warn "VALIDATION WARNING (Fallback): #{validation[:reason]} (allowed due to strictness setting)"
          end
        end

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

  def log_chat_completion_request
    endpoint_url = instance_variable_get(:@custom_endpoint_full_path) ||
                   "#{@client.instance_variable_get(:@uri_base)}/v1/chat/completions"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@client.instance_variable_get(:@access_token)}"
    }

    captain_logger.info '=' * 80
    captain_logger.info "#{self.class.name} Assistant: #{@assistant.id} - Requesting Chat Completion"
    captain_logger.info "Endpoint URL: #{endpoint_url}"
    captain_logger.info "Headers: #{headers.to_json}"
    captain_logger.info "Model: #{@model}"
    captain_logger.info "Number of messages: #{@messages.length}"
    captain_logger.info "Number of tools: #{@tool_registry&.registered_tools&.length || 0}"
    captain_logger.info "Tools: #{(@tool_registry&.registered_tools || []).to_json}"
    captain_logger.info "Messages: #{@messages.to_json}"
    captain_logger.info '=' * 80
  end

  # Check if we should force a documentation search
  # This happens when:
  # 1. We're in an ongoing conversation (not the first message)
  # 2. The user sent a continuation signal (yes, ok, done, next, etc.)
  # 3. The search_documentation tool is available
  # 4. The assistant didn't just offer a handoff (to avoid interfering with handoff flow)
  def should_force_search?
    return false unless @messages.length > 2 # Need at least: system, user, assistant, user
    return false unless @tool_registry&.respond_to?(:search_documentation)

    # Handle both symbol and string keys
    last_user_message = @messages.last&.dig(:content) || @messages.last&.dig('content')
    return false if last_user_message.nil? || last_user_message.strip.empty?

    # Use LLM to intelligently classify the user's message
    classification = classify_user_message_intent(last_user_message)

    case classification
    when 'continuation'
      # User is continuing troubleshooting (e.g., "yes", "done", "next")
      captain_logger.info 'LLM classified as continuation signal - forcing search'
      true
    when 'handoff_confirmation'
      # User is confirming a handoff request (e.g., "yes" after "Would you like to speak with an agent?")
      captain_logger.info 'LLM classified as handoff confirmation - skipping forced search'
      false
    when 'new_question'
      # User asked a new question - let model decide whether to search
      captain_logger.info 'LLM classified as new question - letting model decide'
      false
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
      - "continuation": User acknowledging completion of a step and ready to continue (e.g., "yes", "done", "ok", "next")
      - "handoff_confirmation": User confirming they want to speak with a human agent (only if assistant offered handoff)
      - "new_question": User asking a new question or providing new information

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
        temperature: 0.0,
        max_tokens: 10
      }
    )
    classification_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - classification_start) * 1000).round

    result = classification_response.dig('choices', 0, 'message', 'content')&.strip&.downcase
    captain_logger.info "LLM classification result: #{result} in #{classification_elapsed_ms}ms"

    # Validate result is one of expected values
    %w[continuation handoff_confirmation new_question].include?(result) ? result : nil
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
      return true
    end

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

  # Determine which model to use for classification
  # Use the cheapest/fastest available model, or fall back to main model
  def classification_model
    # Check for classification-specific model config
    classification_model_config = InstallationConfig.find_by(name: 'CAPTAIN_CLASSIFICATION_MODEL')
    return classification_model_config.value if classification_model_config&.value.present?

    # Fall back to main model (though ideally use something lighter/cheaper)
    @model
  end

  # Force a documentation search with context from the conversation
  def force_documentation_search
    # Build search query from conversation context
    # Look back at the last few messages to understand what we're troubleshooting
    recent_context = @messages.last(5)
                              .select { |m| (m[:role] || m['role']) == 'user' || (m[:role] || m['role']) == 'assistant' }
                              .map { |m| m[:content] || m['content'] }
                              .join(' ')

    # Extract key terms (simplified - just use the original problem description)
    user_messages = @messages.select { |m| (m[:role] || m['role']) == 'user' }
    original_problem = user_messages.find { |m| (m[:content] || m['content']).to_s.length > 20 }&.then { |msg| msg[:content] || msg['content'] }

    search_query = original_problem || recent_context.slice(0, 200)

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

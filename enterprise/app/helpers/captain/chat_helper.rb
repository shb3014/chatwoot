module Captain::ChatHelper
  def request_chat_completion
    log_chat_completion_request

    # Initialize response validator if not already present
    # Strictness can be configured via assistant config or globally via InstallationConfig
    strictness = @assistant&.config&.[]('validation_strictness')&.to_sym ||
                 InstallationConfig.find_by(name: 'CAPTAIN_VALIDATION_STRICTNESS')&.value&.to_sym ||
                 :moderate
    @response_validator ||= Captain::ResponseValidatorService.new(strictness: strictness)
    
    # Clear validator at the start of a new user turn (not during recursive tool processing)
    # We detect a new turn by checking if the last message is from the user
    if @messages.last&.dig('role') == 'user'
      Rails.logger.info "Starting new conversation turn - clearing previous documentation"
      @response_validator.clear
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
      Rails.logger.warn "DeepSeek-V3.2: response_format is disabled; relying on prompt + parser fallback for JSON" if has_tools
    elsif thinking_enabled
      # Non-Ark providers typically accept boolean.
      parameters[:thinking] = true
      Rails.logger.warn "Thinking mode enabled - response format constraint removed, relying on prompt for JSON" if has_tools
    elsif is_qwen && has_tools
      Rails.logger.info "Qwen model detected with tools: response_format disabled to enable proper tool calling"
    end

    response = @client.chat(parameters: parameters)

    handle_response(response)
  rescue StandardError => e
    endpoint_url = instance_variable_get(:@custom_endpoint_full_path) ||
                   "#{@client.instance_variable_get(:@uri_base)}/v1/chat/completions"

    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@client.instance_variable_get(:@access_token)}"
    }

    Rails.logger.error "=" * 80
    Rails.logger.error "#{self.class.name} Assistant: #{@assistant.id}, Error in chat completion"
    Rails.logger.error "Error: #{e.class.name} - #{e.message}"
    Rails.logger.error "Request URL: #{endpoint_url}"
    Rails.logger.error "Headers: #{headers.to_json}"
    Rails.logger.error "Model: #{@model}"
    Rails.logger.error "Request Parameters: #{parameters.to_json}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(10).join("\n")}"
    Rails.logger.error "=" * 80
    raise e
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
    Rails.logger.info "=" * 80
    Rails.logger.info "#{self.class.name} Assistant: #{@assistant.id} - Handling Response"
    Rails.logger.info "Full response: #{response.to_json}"

    message = response.dig('choices', 0, 'message')
    
    # Log reasoning content if present (from thinking mode)
    reasoning_content = message['reasoning_content']
    if reasoning_content.present?
      Rails.logger.info "Reasoning content (thinking mode): #{reasoning_content}"
    end
    
    Rails.logger.info "Message extracted: #{message.to_json}"
    Rails.logger.info "Tool calls present: #{message['tool_calls'].present?}"
    Rails.logger.info "Tool calls content: #{message['tool_calls'].to_json}" if message['tool_calls']
    Rails.logger.info "=" * 80

    if message['tool_calls']
      Rails.logger.info "Processing tool calls..."
      process_tool_calls(message['tool_calls'])
    else
      Rails.logger.info "No tool calls, parsing message content as JSON..."
      content = message['content'].strip
      
      # Strip markdown code fences if present (some models like DeepSeek wrap JSON in ```json ... ```)
      content = content.gsub(/\A```json\n/, '').gsub(/\n```\z/, '')
      
      begin
        parsed_message = JSON.parse(content)
        
        # Validate response against captured tool results
        if @response_validator
          validation = @response_validator.validate_response(parsed_message['response'] || '')
          
          Rails.logger.info "=" * 80
          Rails.logger.info "Response Validation:"
          Rails.logger.info "Valid: #{validation[:valid]}"
          Rails.logger.info "Reason: #{validation[:reason]}"
          Rails.logger.info "Confidence: #{validation[:confidence]}"
          Rails.logger.info "Should Reject: #{validation[:should_reject]}"
          Rails.logger.info "Strictness: #{@response_validator.instance_variable_get(:@strictness)}"
          Rails.logger.info "Documentation content available: #{@response_validator.get_documentation_content.length} chars"
          Rails.logger.info "Indicators: #{validation[:indicators]&.join(', ') || 'none'}" if validation[:indicators]
          Rails.logger.info "=" * 80
          
          # If validation determines response should be rejected, force a safe response
          if validation[:should_reject]
            Rails.logger.error "VALIDATION REJECTED: #{validation[:reason]}"
            Rails.logger.error "Original response: #{parsed_message['response']}"
            
            # Force a safe response
            parsed_message = {
              'reasoning' => "Response validation detected potential issues. Unable to provide accurate information from documentation.",
              'response' => "I apologize, but I couldn't find reliable information about that in our documentation. Would you like to speak with a support agent who can help you better?"
            }
          elsif !validation[:valid]
            # Log warning but allow response (based on strictness setting)
            Rails.logger.warn "VALIDATION WARNING: #{validation[:reason]} (allowed due to strictness setting)"
          end
        end
        
        persist_message(parsed_message, 'assistant')
        parsed_message
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse response as JSON: #{e.message}"
        Rails.logger.error "Response content: #{content}"
        
        # Fallback: wrap plain text response in expected JSON structure
        fallback_message = {
          'reasoning' => reasoning_content || 'Model returned non-JSON response',
          'response' => content
        }
        Rails.logger.warn "Using fallback JSON structure: #{fallback_message.to_json}"
        
        # Validate the fallback response too
        if @response_validator
          validation = @response_validator.validate_response(fallback_message['response'] || '')
          
          Rails.logger.info "=" * 80
          Rails.logger.info "Response Validation (Fallback):"
          Rails.logger.info "Valid: #{validation[:valid]}"
          Rails.logger.info "Reason: #{validation[:reason]}"
          Rails.logger.info "Confidence: #{validation[:confidence]}"
          Rails.logger.info "Should Reject: #{validation[:should_reject]}"
          Rails.logger.info "Strictness: #{@response_validator.instance_variable_get(:@strictness)}"
          Rails.logger.info "Documentation content available: #{@response_validator.get_documentation_content.length} chars"
          Rails.logger.info "Indicators: #{validation[:indicators]&.join(', ') || 'none'}" if validation[:indicators]
          Rails.logger.info "=" * 80
          
          # If validation determines response should be rejected, force a safe response
          if validation[:should_reject]
            Rails.logger.error "VALIDATION REJECTED (Fallback): #{validation[:reason]}"
            Rails.logger.error "Original response: #{fallback_message['response']}"
            
            # Force a safe response
            fallback_message = {
              'reasoning' => "Response validation detected potential issues. Unable to provide accurate information from documentation.",
              'response' => "I apologize, but I couldn't find reliable information about that in our documentation. Would you like to speak with a support agent who can help you better?"
            }
          elsif !validation[:valid]
            # Log warning but allow response (based on strictness setting)
            Rails.logger.warn "VALIDATION WARNING (Fallback): #{validation[:reason]} (allowed due to strictness setting)"
          end
        end
        
        persist_message(fallback_message, 'assistant')
        fallback_message
      end
    end
  end

  def process_tool_calls(tool_calls)
    append_tool_calls(tool_calls)
    tool_calls.each do |tool_call|
      process_tool_call(tool_call)
    end
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
    persist_message(
      {
        content: I18n.t('captain.copilot.using_tool', function_name: function_name),
        function_name: function_name
      },
      'assistant_thinking'
    )
    result = @tool_registry.send(function_name, arguments)
    
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

    Rails.logger.info "=" * 80
    Rails.logger.info "#{self.class.name} Assistant: #{@assistant.id} - Requesting Chat Completion"
    Rails.logger.info "Endpoint URL: #{endpoint_url}"
    Rails.logger.info "Headers: #{headers.to_json}"
    Rails.logger.info "Model: #{@model}"
    Rails.logger.info "Number of messages: #{@messages.length}"
    Rails.logger.info "Number of tools: #{@tool_registry&.registered_tools&.length || 0}"
    Rails.logger.info "Tools: #{(@tool_registry&.registered_tools || []).to_json}"
    Rails.logger.info "Messages: #{@messages.to_json}"
    Rails.logger.info "=" * 80
  end
end

module Captain::ChatHelper
  def request_chat_completion
    log_chat_completion_request

    # Check if thinking mode is enabled (for models like DeepSeek-v3.2)
    thinking_config = InstallationConfig.find_by(name: 'CAPTAIN_THINKING_ENABLED')
    thinking_enabled = thinking_config&.value.present? && ActiveModel::Type::Boolean.new.cast(thinking_config.value)

    tools = @tool_registry&.registered_tools || []
    has_tools = tools.any?

    parameters = {
      model: @model,
      messages: @messages,
      tools: tools,
      temperature: @assistant&.config&.[]('temperature').to_f || 1
    }

    # Some OpenAI-compatible providers require tool_choice explicitly for tool calling.
    parameters[:tool_choice] = 'auto' if has_tools

    # Only add response_format if thinking is NOT enabled
    # (thinking mode conflicts with json_object format in DeepSeek-v3.2)
    # When thinking is disabled, always use JSON format for structured outputs
    unless thinking_enabled
      parameters[:response_format] = { type: 'json_object' }
    end

    # Add thinking parameter if enabled (note: may not work well with tools)
    if thinking_enabled
      parameters[:thinking] = true
      Rails.logger.warn "Thinking mode enabled - response format constraint removed, relying on prompt for JSON" if has_tools
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

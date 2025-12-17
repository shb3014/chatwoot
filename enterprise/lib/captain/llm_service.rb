require 'openai'

class Captain::LlmService
  def initialize(config)
    @client = OpenAI::Client.new(
      access_token: config[:api_key],
      log_errors: Rails.env.development?
    )
    @logger = Rails.logger
  end

  def call(messages, functions = [])
    # Check if thinking mode is enabled (for models like DeepSeek-v3.2)
    thinking_config = InstallationConfig.find_by(name: 'CAPTAIN_THINKING_ENABLED')
    thinking_enabled = thinking_config&.value.present? && ActiveModel::Type::Boolean.new.cast(thinking_config.value)

    openai_params = {
      model: model,
      messages: messages
    }
    
    # Only add response_format if thinking is NOT enabled (thinking mode conflicts with json_object format)
    openai_params[:response_format] = { type: 'json_object' } unless thinking_enabled
    
    if functions.any?
      openai_params[:tools] = functions
      # Some OpenAI-compatible providers require tool_choice explicitly for tool calling.
      openai_params[:tool_choice] = 'auto'
    end
    
    # Add thinking parameter if enabled
    openai_params[:thinking] = true if thinking_enabled

    response = @client.chat(parameters: openai_params)
    handle_response(response)
  rescue StandardError => e
    handle_error(e)
  end

  private

  def model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || ENV.fetch('OPENAI_GPT_MODEL', 'gpt-4o-mini')
  end

  def handle_response(response)
    if response['choices'][0]['message']['tool_calls']
      handle_tool_calls(response)
    else
      handle_direct_response(response)
    end
  end

  def handle_tool_calls(response)
    tool_call = response['choices'][0]['message']['tool_calls'][0]
    {
      tool_call: tool_call,
      output: nil,
      stop: false
    }
  end

  def handle_direct_response(response)
    message = response.dig('choices', 0, 'message') || {}
    content = message['content'].to_s.strip

    # Strip markdown code fences if present (some models like DeepSeek wrap JSON in ```json ... ```)
    content = content.gsub(/\A```json\n/, '').gsub(/\n```\z/, '')

    begin
      parsed = JSON.parse(content)
    rescue JSON::ParserError => e
      # DeepSeek-V3.2 thinking mode can return non-JSON content unless response_format is enforced.
      # Fallback to returning plain text as output so caller doesn't keep retrying forever.
      @logger.error("Failed to parse response as JSON: #{e.message}")
      @logger.error("Content: #{content}")
      reasoning_content = message['reasoning_content'].presence || 'Model returned non-JSON response'
      parsed = { 'result' => content, 'thought_process' => reasoning_content, 'stop' => false }
    end

    {
      output: parsed['result'] || parsed['thought_process'],
      stop: parsed['stop'] || false
    }
  end

  def handle_error(error, content = nil)
    @logger.error("LLM call failed: #{error.message}")
    @logger.error(error.backtrace.join("\n"))
    @logger.error("Content: #{content}") if content

    { output: 'Error occurred, retrying', stop: false }
  end
end

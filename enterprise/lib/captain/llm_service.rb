require 'openai'

class Captain::LlmService
  def initialize(config)
    @client = OpenAI::Client.new(
      access_token: config[:api_key],
      log_errors: Rails.env.development?,
      faraday_middleware: faraday_proxy_middleware
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

    is_deepseek_v32 = deepseek_v32_model?(model)
    is_qwen = qwen_model?(model)
    has_tools = functions.any?

    # response_format: json_object is not supported by Ark DeepSeek-V3.2 (even when thinking is disabled).
    # Qwen models also don't work well with response_format when tools are present - they return JSON content
    # directly instead of using tool_calls mechanism.
    # So we only enforce response_format for models that support it properly.
    openai_params[:response_format] = { type: 'json_object' } if !thinking_enabled && !is_deepseek_v32 && !(is_qwen && has_tools)

    if has_tools
      openai_params[:tools] = functions
      # Some OpenAI-compatible providers require tool_choice explicitly for tool calling.
      openai_params[:tool_choice] = 'auto'
    end

    # Ark DeepSeek-V3.2 expects a thinking object: { type: "enabled" | "disabled" }.
    if is_deepseek_v32
      openai_params[:thinking] = ark_thinking_param(thinking_enabled)
      @logger.warn 'DeepSeek-V3.2: response_format is disabled; relying on prompt + parser fallback for JSON' if has_tools
    elsif thinking_enabled
      openai_params[:thinking] = true
      openai_params[:enable_thinking] = true if is_qwen
      @logger.warn 'Thinking mode enabled - response format constraint removed, relying on prompt for JSON' if has_tools
    elsif is_qwen
      openai_params[:enable_thinking] = false
      @logger.info 'Qwen model detected with tools: response_format disabled to enable proper tool calling' if has_tools
    end

    response = @client.chat(parameters: openai_params)
    handle_response(response)
  rescue StandardError => e
    handle_error(e)
  end

  private

  def deepseek_v32_model?(model_name)
    model_str = model_name.to_s
    model_str.match?(/deepseek[-_]?v3[-_]?2/i) || model_str.match?(/deepseek[-_]?v3\.2/i)
  end

  def qwen_model?(model_name)
    model_str = model_name.to_s
    model_str.match?(/qwen/i)
  end

  def ark_thinking_param(enabled)
    { type: enabled ? 'enabled' : 'disabled' }
  end

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

  def faraday_proxy_middleware
    proxy_url = proxy_url_for_requests
    return nil if proxy_url.blank?

    proc { |connection| connection.proxy = proxy_url }
  end

  def proxy_url_for_requests
    proxy_url = ENV['HTTPS_PROXY'].presence || ENV['https_proxy'].presence ||
                ENV['HTTP_PROXY'].presence || ENV['http_proxy'].presence ||
                proxy_url_from_env_file
    if proxy_url.present? && !defined?(@proxy_log_emitted)
      @logger.info("[Captain][Proxy] Using proxy_url=#{proxy_url}")
      @proxy_log_emitted = true
    end

    proxy_url
  end

  def proxy_url_from_env_file
    @proxy_url_from_env_file ||= begin
      env_path = Rails.root.join('.env')
      if env_path.exist?

        entries = {}
        env_path.read.each_line do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?('#')

          key, value = stripped.split('=', 2)
          next if key.blank? || value.blank?

          entries[key] = value
        end

        entries['HTTPS_PROXY'].presence || entries['https_proxy'].presence ||
          entries['HTTP_PROXY'].presence || entries['http_proxy'].presence
      end
    rescue StandardError
      nil
    end
  end
end

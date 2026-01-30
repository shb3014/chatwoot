require 'net/http'

class Llm::BaseOpenAiService
  DEFAULT_MODEL = 'gpt-4o-mini'.freeze

  def initialize
    @main_api_key = normalize_open_ai_api_key
    setup_endpoint
    setup_model

    raise 'CAPTAIN_OPEN_AI_API_KEY not configured' if @main_api_key.blank?

    @client = OpenAI::Client.new(
      access_token: @main_api_key,
      uri_base: @uri_base,
      log_errors: Rails.env.development?,
      faraday_middleware: faraday_proxy_middleware
    )

    # Determine if we need to patch embeddings (custom endpoint or custom API key)
    @patch_embeddings = @custom_embeddings_endpoint.present? || @embedding_api_key.present?

    # Override the request_uri to use custom endpoint directly
    # Patch if either custom chat endpoint or custom embeddings configuration is present
    patch_client_for_custom_endpoint if @custom_endpoint_full_path.present? || @patch_embeddings
  rescue StandardError => e
    raise "Failed to initialize OpenAI client: #{e.message}"
  end

  private

  def normalize_open_ai_api_key
    raw_api_key = fetch_installation_config_value('CAPTAIN_OPEN_AI_API_KEY')
    return raw_api_key if raw_api_key.blank? || !raw_api_key.match?(%r{\Ahttps?://})

    @endpoint_override_from_api_key = raw_api_key
    ENV['OPENAI_API_KEY'].presence
  end

  def fetch_installation_config_value(name)
    InstallationConfig.find_by(name: name)&.value || begin
      ConfigLoader.new.process
      InstallationConfig.find_by(name: name)&.value
    end
  end

  def setup_endpoint
    full_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    if @endpoint_override_from_api_key.present? &&
       (full_endpoint.blank? || full_endpoint == 'https://api.openai.com' || full_endpoint == 'https://api.openai.com/')
      full_endpoint = @endpoint_override_from_api_key
    end
    full_endpoint = (full_endpoint.presence || 'https://api.openai.com/').chomp('/')
    endpoint_path = begin
      URI.parse(full_endpoint).path
    rescue StandardError
      ''
    end

    # Check for custom embedding endpoint configuration
    custom_embedding_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_ENDPOINT')&.value

    # Check for custom embedding API key (falls back to OpenAI API key if not set)
    @embedding_api_key = InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_API_KEY')&.value

    # If the endpoint already contains /v1/chat/completions, strip it for the uri_base
    # Otherwise, assume it's a custom endpoint with a different path structure
    #
    # If a proxy is configured and the endpoint is non-OpenAI, force custom HTTP
    # handling so HTTParty can apply proxy settings reliably.
    if full_endpoint.end_with?('/v1/chat/completions') &&
       proxy_url_for_requests.present? &&
       !full_endpoint.start_with?('https://api.openai.com')
      @uri_base = full_endpoint
      @custom_endpoint_full_path = full_endpoint

      # Use custom embedding endpoint if configured, otherwise derive from chat endpoint
      @custom_embeddings_endpoint = if custom_embedding_endpoint.present?
                                      custom_embedding_endpoint.chomp('/')
                                    else
                                      full_endpoint.gsub('chat/completions', 'embeddings')
                                    end
    elsif full_endpoint.end_with?('/v1/chat/completions')
      @uri_base = full_endpoint.gsub(%r{/v1/chat/completions$}, '')
      @custom_endpoint_full_path = nil
      @custom_embeddings_endpoint = custom_embedding_endpoint.presence
    elsif full_endpoint.match?(%r{/v1/?$})
      @uri_base = "#{full_endpoint.chomp('/')}/"
      @custom_endpoint_full_path = nil
      @custom_embeddings_endpoint = custom_embedding_endpoint.presence
    elsif endpoint_path.blank? || endpoint_path == '/'
      @uri_base = "#{full_endpoint.chomp('/')}/"
      @custom_endpoint_full_path = nil
      @custom_embeddings_endpoint = custom_embedding_endpoint.presence
    else
      # Custom endpoint with non-standard path - use it directly
      @uri_base = full_endpoint
      @custom_endpoint_full_path = full_endpoint

      # Use custom embedding endpoint if configured, otherwise derive from chat endpoint
      @custom_embeddings_endpoint = if custom_embedding_endpoint.present?
                                      custom_embedding_endpoint.chomp('/')
                                    elsif full_endpoint.include?('chat/completions')
                                      # Generate embeddings endpoint by replacing chat/completions with embeddings
                                      full_endpoint.gsub('chat/completions', 'embeddings')
                                    else
                                      # Fallback to same endpoint if pattern not found
                                      full_endpoint
                                    end
    end
  end

  def patch_client_for_custom_endpoint
    # Store the custom endpoints and API keys
    custom_chat_path = @custom_endpoint_full_path
    custom_embeddings_path = @custom_embeddings_endpoint
    main_api_key = @main_api_key
    embedding_api_key = @embedding_api_key.presence || main_api_key
    uri_base = @uri_base
    logger = captain_logger
    proxy_options = http_proxy_options

    # Monkey-patch the client instance to override the chat endpoint (only if custom chat endpoint is set)
    if custom_chat_path.present?
      @client.define_singleton_method(:chat) do |parameters:, stream: nil|
        # Make direct HTTP request to custom endpoint instead of using gem's path
        headers = {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{main_api_key}"
        }

        # Handle streaming requests
        if stream.is_a?(Proc)
          # Add stream: true to parameters for SSE streaming
          streaming_params = parameters.merge(stream: true)

          logger.info('=' * 80)
          logger.info("Calling custom chat endpoint (streaming): #{custom_chat_path}")
          logger.info("Headers: #{headers.to_json}")
          logger.info("Request body: #{streaming_params.to_json}")

          uri = URI.parse(custom_chat_path)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.read_timeout = 120

          # Configure proxy if present
          if proxy_options[:http_proxyaddr].present?
            http = Net::HTTP.new(
              uri.host, uri.port,
              proxy_options[:http_proxyaddr],
              proxy_options[:http_proxyport]
            )
            http.use_ssl = (uri.scheme == 'https')
            http.read_timeout = 120
          end

          request = Net::HTTP::Post.new(uri.request_uri)
          headers.each { |k, v| request[k] = v }
          request.body = streaming_params.to_json

          http.request(request) do |response|
            unless response.is_a?(Net::HTTPSuccess)
              error_body = response.body
              logger.warn("Streaming response error: #{response.code} - #{error_body}")
              raise OpenAI::Error, "HTTP #{response.code}: #{error_body}"
            end

            # Buffer to handle partial lines across TCP chunks
            buffer = +''

            response.read_body do |chunk|
              buffer << chunk

              # Process complete lines from buffer
              while (newline_idx = buffer.index("\n"))
                line = buffer.slice!(0..newline_idx).strip
                next if line.empty?
                next unless line.start_with?('data: ')

                data = line.sub(/^data: /, '')
                next if data == '[DONE]'

                begin
                  parsed = JSON.parse(data)
                  stream.call(parsed)
                rescue JSON::ParserError => e
                  logger.warn("Failed to parse streaming chunk: #{e.message} - #{data}")
                end
              end
            end

            # Process any remaining data in buffer
            if buffer.strip.start_with?('data: ')
              data = buffer.strip.sub(/^data: /, '')
              unless data == '[DONE]'
                begin
                  parsed = JSON.parse(data)
                  stream.call(parsed)
                rescue JSON::ParserError => e
                  logger.warn("Failed to parse final streaming chunk: #{e.message} - #{data}")
                end
              end
            end
          end

          logger.info('=' * 80)
          logger.info('Streaming completed')

          # Return nil for streaming - the caller handles building the response
          nil
        else
          # Non-streaming request
          logger.info('=' * 80)
          logger.info("Calling custom chat endpoint: #{custom_chat_path}")
          logger.info("Headers: #{headers.to_json}")
          logger.info("Request body: #{parameters.to_json}")

          response = HTTParty.post(
            custom_chat_path,
            headers: headers,
            body: parameters.to_json,
            **proxy_options
          )

          logger.info("Response status: #{response.code}")
          logger.info("Response body: #{response.body}")
          logger.info('=' * 80)

          raise OpenAI::Error, "HTTP #{response.code}: #{response.body}" unless response.success?

          JSON.parse(response.body)
        end
      end
    end

    # Patch embeddings if custom endpoint or custom API key is configured
    return unless @patch_embeddings

    @client.define_singleton_method(:embeddings) do |parameters:|
      # Use embedding-specific API key if configured, otherwise use main API key
      headers = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{embedding_api_key}"
      }

      # Determine the embeddings endpoint
      embeddings_endpoint = (custom_embeddings_path.presence || "#{uri_base}/v1/embeddings")

      logger.info('=' * 80)
      logger.info("Calling embeddings endpoint: #{embeddings_endpoint}")
      logger.info("Headers: #{headers.to_json}")
      logger.info("Request body: #{parameters.to_json}")

      response = HTTParty.post(
        embeddings_endpoint,
        headers: headers,
        body: parameters.to_json,
        **proxy_options
      )

      logger.info("Response status: #{response.code}")
      logger.info("Response body: #{response.body}")
      logger.info('=' * 80)

      raise OpenAI::Error, "HTTP #{response.code}: #{response.body}" unless response.success?

      JSON.parse(response.body)
    end
  end

  def setup_model
    config_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
    @model = (config_value.presence || DEFAULT_MODEL)
  end

  def captain_logger
    Captain::Logger.logger
  rescue NameError
    Rails.logger
  end

  def http_proxy_options
    proxy_url = proxy_url_for_requests
    return {} if proxy_url.blank?

    uri = URI.parse(proxy_url)
    {
      http_proxyaddr: uri.host,
      http_proxyport: uri.port,
      http_proxyuser: uri.user,
      http_proxypass: uri.password
    }.compact
  rescue URI::InvalidURIError
    {}
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
      captain_logger.info("[Captain][Proxy] Using proxy_url=#{proxy_url}")
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

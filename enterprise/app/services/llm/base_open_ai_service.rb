class Llm::BaseOpenAiService
  DEFAULT_MODEL = 'gpt-4o-mini'.freeze

  def initialize
    setup_endpoint
    setup_model

    @main_api_key = InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value

    @client = OpenAI::Client.new(
      access_token: @main_api_key,
      uri_base: @uri_base,
      log_errors: Rails.env.development?
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

  def setup_endpoint
    full_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    full_endpoint = (full_endpoint.presence || 'https://api.openai.com/').chomp('/')

    # Check for custom embedding endpoint configuration
    custom_embedding_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_ENDPOINT')&.value

    # Check for custom embedding API key (falls back to OpenAI API key if not set)
    @embedding_api_key = InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_API_KEY')&.value

    # If the endpoint already contains /v1/chat/completions, strip it for the uri_base
    # Otherwise, assume it's a custom endpoint with a different path structure
    if full_endpoint.end_with?('/v1/chat/completions')
      @uri_base = full_endpoint.gsub(%r{/v1/chat/completions$}, '')
      @custom_endpoint_full_path = nil
      @custom_embeddings_endpoint = custom_embedding_endpoint.presence
    elsif full_endpoint == 'https://api.openai.com' || full_endpoint == 'https://api.openai.com/'
      # Standard OpenAI endpoint
      @uri_base = 'https://api.openai.com/'
      @custom_endpoint_full_path = nil
      @custom_embeddings_endpoint = custom_embedding_endpoint.presence
    else
      # Custom endpoint with non-standard path - use it directly
      @uri_base = full_endpoint
      @custom_endpoint_full_path = full_endpoint

      # Use custom embedding endpoint if configured, otherwise derive from chat endpoint
      if custom_embedding_endpoint.present?
        @custom_embeddings_endpoint = custom_embedding_endpoint.chomp('/')
      elsif full_endpoint.include?('chat/completions')
        # Generate embeddings endpoint by replacing chat/completions with embeddings
        @custom_embeddings_endpoint = full_endpoint.gsub('chat/completions', 'embeddings')
      else
        # Fallback to same endpoint if pattern not found
        @custom_embeddings_endpoint = full_endpoint
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

    # Monkey-patch the client instance to override the chat endpoint (only if custom chat endpoint is set)
    if custom_chat_path.present?
      @client.define_singleton_method(:chat) do |parameters:|
        # Make direct HTTP request to custom endpoint instead of using gem's path
        headers = {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{main_api_key}"
        }

        Rails.logger.info("=" * 80)
        Rails.logger.info("Calling custom chat endpoint: #{custom_chat_path}")
        Rails.logger.info("Headers: #{headers.to_json}")
        Rails.logger.info("Request body: #{parameters.to_json}")

        response = HTTParty.post(
          custom_chat_path,
          headers: headers,
          body: parameters.to_json
        )

        Rails.logger.info("Response status: #{response.code}")
        Rails.logger.info("Response body: #{response.body}")
        Rails.logger.info("=" * 80)

        if response.success?
          JSON.parse(response.body)
        else
          raise OpenAI::Error, "HTTP #{response.code}: #{response.body}"
        end
      end
    end

    # Patch embeddings if custom endpoint or custom API key is configured
    if @patch_embeddings
      @client.define_singleton_method(:embeddings) do |parameters:|
        # Use embedding-specific API key if configured, otherwise use main API key
        headers = {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{embedding_api_key}"
        }

        # Determine the embeddings endpoint
        embeddings_endpoint = if custom_embeddings_path.present?
                                custom_embeddings_path
                              else
                                # Use standard OpenAI embeddings endpoint
                                "#{uri_base}/v1/embeddings"
                              end

        Rails.logger.info("=" * 80)
        Rails.logger.info("Calling embeddings endpoint: #{embeddings_endpoint}")
        Rails.logger.info("Headers: #{headers.to_json}")
        Rails.logger.info("Request body: #{parameters.to_json}")

        response = HTTParty.post(
          embeddings_endpoint,
          headers: headers,
          body: parameters.to_json
        )

        Rails.logger.info("Response status: #{response.code}")
        Rails.logger.info("Response body: #{response.body}")
        Rails.logger.info("=" * 80)

        if response.success?
          JSON.parse(response.body)
        else
          raise OpenAI::Error, "HTTP #{response.code}: #{response.body}"
        end
      end
    end
  end

  def setup_model
    config_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
    @model = (config_value.presence || DEFAULT_MODEL)
  end
end

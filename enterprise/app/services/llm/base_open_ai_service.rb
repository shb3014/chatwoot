class Llm::BaseOpenAiService
  DEFAULT_MODEL = 'gpt-4o-mini'.freeze

  def initialize
    setup_endpoint
    setup_model
    
    @client = OpenAI::Client.new(
      access_token: InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value,
      uri_base: @uri_base,
      log_errors: Rails.env.development?
    )
    
    # Override the request_uri to use custom endpoint directly
    patch_client_for_custom_endpoint if @custom_endpoint_full_path.present?
  rescue StandardError => e
    raise "Failed to initialize OpenAI client: #{e.message}"
  end

  private

  def setup_endpoint
    full_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    full_endpoint = (full_endpoint.presence || 'https://api.openai.com/').chomp('/')
    
    # If the endpoint already contains /v1/chat/completions, strip it for the uri_base
    # Otherwise, assume it's a custom endpoint with a different path structure
    if full_endpoint.end_with?('/v1/chat/completions')
      @uri_base = full_endpoint.gsub(%r{/v1/chat/completions$}, '')
      @custom_endpoint_full_path = nil
      @custom_embeddings_endpoint = nil
    elsif full_endpoint == 'https://api.openai.com' || full_endpoint == 'https://api.openai.com/'
      # Standard OpenAI endpoint
      @uri_base = 'https://api.openai.com/'
      @custom_endpoint_full_path = nil
      @custom_embeddings_endpoint = nil
    else
      # Custom endpoint with non-standard path - use it directly
      # For embeddings, replace 'chat/completions' with 'embeddings' if present
      @uri_base = full_endpoint
      @custom_endpoint_full_path = full_endpoint
      
      # Generate embeddings endpoint by replacing chat/completions with embeddings
      if full_endpoint.include?('chat/completions')
        @custom_embeddings_endpoint = full_endpoint.gsub('chat/completions', 'embeddings')
      else
        # Fallback to same endpoint if pattern not found
        @custom_embeddings_endpoint = full_endpoint
      end
    end
  end

  def patch_client_for_custom_endpoint
    # Store the custom endpoints
    custom_chat_path = @custom_endpoint_full_path
    custom_embeddings_path = @custom_embeddings_endpoint
    
    # Monkey-patch the client instance to override the chat endpoint
    @client.define_singleton_method(:chat) do |parameters:|
      # Make direct HTTP request to custom endpoint instead of using gem's path
      headers = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@access_token}"
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
    
    # Also patch embeddings endpoint for custom endpoints
    # Embeddings endpoint is derived by replacing 'chat/completions' with 'embeddings'
    @client.define_singleton_method(:embeddings) do |parameters:|
      headers = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@access_token}"
      }
      
      Rails.logger.info("=" * 80)
      Rails.logger.info("Calling custom embeddings endpoint: #{custom_embeddings_path}")
      Rails.logger.info("Headers: #{headers.to_json}")
      Rails.logger.info("Request body: #{parameters.to_json}")
      
      response = HTTParty.post(
        custom_embeddings_path,
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

  def setup_model
    config_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
    @model = (config_value.presence || DEFAULT_MODEL)
  end
end

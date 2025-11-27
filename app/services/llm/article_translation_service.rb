require 'openai'

module Llm
  class ArticleTranslationService
    def initialize(article, target_locale)
      @article = article
      @target_locale = target_locale

      # Use BaseOpenAiService logic to setup endpoint and client
      # This mimics how Llm::BaseOpenAiService initializes
      setup_endpoint
      setup_model

      @main_api_key = InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value

      @client = OpenAI::Client.new(
        access_token: @main_api_key,
        uri_base: @uri_base,
        request_timeout: 60,
        log_errors: Rails.env.development?
      )

      # Monkey-patch the client instance if custom endpoint is present
      # This is critical for DeepSeek support if it uses a non-standard path
      patch_client_for_custom_endpoint if @custom_endpoint_full_path.present?
    end

    def translate
      return nil unless @article
      return nil if @target_locale.blank?

      translated_title = translate_text(@article.title, "title")
      translated_content = translate_text(@article.content, "content")

      # Description is optional
      translated_description = @article.description.present? ? translate_text(@article.description, "description") : nil

      {
        title: translated_title,
        content: translated_content,
        description: translated_description
      }
    end

    private

    def setup_endpoint
      full_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
      full_endpoint = (full_endpoint.presence || 'https://api.openai.com/').chomp('/')

      # Logic copied from Llm::BaseOpenAiService#setup_endpoint
      if full_endpoint.end_with?('/v1/chat/completions')
        @uri_base = full_endpoint.gsub(%r{/v1/chat/completions$}, '')
        @custom_endpoint_full_path = nil
      elsif full_endpoint == 'https://api.openai.com' || full_endpoint == 'https://api.openai.com/'
        @uri_base = 'https://api.openai.com/'
        @custom_endpoint_full_path = nil
      else
        # Custom endpoint with non-standard path - use it directly
        @uri_base = full_endpoint
        @custom_endpoint_full_path = full_endpoint
      end
    end

    def setup_model
      config_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
      @model = (config_value.presence || 'gpt-4o-mini')
    end

    def patch_client_for_custom_endpoint
      custom_chat_path = @custom_endpoint_full_path
      main_api_key = @main_api_key

      @client.define_singleton_method(:chat) do |parameters:|
        headers = {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{main_api_key}"
        }

        Rails.logger.info("=" * 80)
        Rails.logger.info("Calling custom chat endpoint: #{custom_chat_path}")

        response = HTTParty.post(
          custom_chat_path,
          headers: headers,
          body: parameters.to_json,
          timeout: 60
        )

        Rails.logger.info("Response status: #{response.code}")

        if response.success?
          JSON.parse(response.body)
        else
          raise OpenAI::Error, "HTTP #{response.code}: #{response.body}"
        end
      end
    end

    def translate_text(text, type)
      return text if text.blank?

      prompt = "You are a helpful assistant that translates help center articles. " \
               "Translate the following #{type} to #{@target_locale}. " \
               "Preserve all HTML tags and formatting exactly as they are. " \
               "Do not add any explanations or surrounding text. " \
               "Return ONLY the translated text."

      response = @client.chat(
        parameters: {
          model: @model,
          messages: [
            { role: "system", content: prompt },
            { role: "user", content: text }
          ]
        }
      )

      response.dig("choices", 0, "message", "content")&.strip
    rescue StandardError => e
      Rails.logger.error "[ArticleTranslationService] Translation failed: #{e.message}"
      nil
    end
  end
end


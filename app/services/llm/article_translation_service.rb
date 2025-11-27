require 'openai'

module Llm
  class ArticleTranslationService
    def initialize(article, target_locale)
      @article = article
      @target_locale = target_locale

      api_key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
      @model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value || 'gpt-4o-mini'

      api_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
      uri_base = api_endpoint.present? ? api_endpoint.chomp('/') : nil

      @client = OpenAI::Client.new(
        access_token: api_key,
        uri_base: uri_base,
        request_timeout: 60
      )
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


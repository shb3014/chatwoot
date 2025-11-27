module Llm
  class ArticleTranslationService
    def initialize(article, target_locale)
      @article = article
      @target_locale = target_locale
      @client = Agents::OpenAI.new
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
          model: Agents.config.default_model,
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


class Llm::ArticleTranslationService < Llm::BaseOpenAiService
  def initialize(article, target_locale)
    super(model_type: :fast)
    @article = article
    @target_locale = target_locale
  end

  def translate
    return nil unless @article
    return nil if @target_locale.blank?

    captain_logger.info "[ArticleTranslationService] Starting translation of article #{@article.id} " \
                        "to #{@target_locale} using model=#{@model}"

    translated_title = translate_text(@article.title, 'title')
    translated_content = translate_text(@article.content, 'content')
    translated_description = @article.description.present? ? translate_text(@article.description, 'description') : nil

    if translated_title.blank? || translated_content.blank?
      captain_logger.error "[ArticleTranslationService] Translation returned blank title or content for article #{@article.id} " \
                           "(title_blank=#{translated_title.blank?}, content_blank=#{translated_content.blank?})"
      return nil
    end

    captain_logger.info "[ArticleTranslationService] All translations completed for article #{@article.id}"

    {
      title: translated_title,
      content: translated_content,
      description: translated_description
    }
  end

  private

  def translate_text(text, type)
    return text if text.blank?

    captain_logger.info "[ArticleTranslationService] Translating #{type} (#{text.length} chars)..."

    prompt = 'You are a helpful assistant that translates help center articles. ' \
             "Translate the following #{type} to #{@target_locale}. " \
             'Preserve all HTML tags and formatting exactly as they are. ' \
             'Do not add any explanations or surrounding text. ' \
             'Return ONLY the translated text.'

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = @client.chat(
      parameters: {
        model: @model,
        messages: [
          { role: 'system', content: prompt },
          { role: 'user', content: text }
        ]
      }
    )
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    result = response.dig('choices', 0, 'message', 'content')&.strip
    captain_logger.info "[ArticleTranslationService] Translated #{type} in #{elapsed_ms}ms (#{text.length} -> #{result&.length || 0} chars)"
    result
  rescue StandardError => e
    captain_logger.error "[ArticleTranslationService] Translation of #{type} failed: #{e.class} — #{e.message}"
    captain_logger.error "[ArticleTranslationService] Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
    nil
  end
end

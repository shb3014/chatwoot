class MessageTemplates::Template::EmailCollect
  pattr_initialize [:conversation!]

  def perform
    ActiveRecord::Base.transaction do
      conversation.messages.create!(ways_to_reach_you_message_params)
      conversation.messages.create!(email_input_box_template_message_params)
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    true
  end

  private

  delegate :contact, :account, to: :conversation
  delegate :inbox, to: :message

  def ways_to_reach_you_message_params
    base_content = I18n.with_locale(template_locale) do
      I18n.t('conversations.templates.ways_to_reach_you_message_body',
             account_name: account.name)
    end

    translated_content = translate_message(base_content)

    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :template,
      content: translated_content
    }
  end

  def email_input_box_template_message_params
    base_content = I18n.with_locale(template_locale) do
      I18n.t('conversations.templates.email_input_box_message_body',
             account_name: account.name)
    end

    translated_content = translate_message(base_content)

    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :template,
      content_type: :input_email,
      content: translated_content
    }
  end

  def translate_message(message)
    return message unless defined?(Llm::TranslationService)

    # Skip LLM translation if i18n already provided a translation in the user's locale
    # This avoids wasteful LLM calls when we already have the message in the correct language
    user_language = detect_user_language
    i18n_locale_language = template_locale.to_s.split('_').first

    if user_language.present? && i18n_locale_language.present? && user_language == i18n_locale_language
      Rails.logger.info "[EmailCollect] Skipping LLM translation - i18n already provided #{i18n_locale_language} translation"
      return message
    end

    Llm::TranslationService.new(conversation).translate_message(message)
  rescue StandardError => e
    Rails.logger.error "[EmailCollect] Translation failed: #{e.message}"
    message
  end

  def detect_user_language
    # Detect the user's language from conversation or browser language
    language = conversation.additional_attributes&.dig('conversation_language') ||
               conversation.additional_attributes&.dig('browser_language')
    language.to_s.split(/[-_]/).first.presence
  end

  def template_locale
    @template_locale ||= begin
      locale_from_conversation =
        conversation.additional_attributes&.dig('conversation_language') ||
        conversation.additional_attributes&.dig('browser_language')

      Rails.logger.info(
        "[EmailCollect] resolved locale: conversation_language=#{conversation.additional_attributes&.dig('conversation_language')}, " \
        "browser_language=#{conversation.additional_attributes&.dig('browser_language')}, " \
        "account_locale=#{account.locale}"
      )

      normalized_locale(locale_from_conversation) ||
        normalized_locale(account.locale) ||
        I18n.default_locale
    end
  end

  def normalized_locale(locale)
    return if locale.blank?

    locale_str = locale.to_s.tr('-', '_')
    available_locales = I18n.available_locales.map(&:to_s)
    return locale_str if available_locales.include?(locale_str)

    locale_without_variant = locale_str.split('_')[0]
    return locale_without_variant if available_locales.include?(locale_without_variant)
  end
end

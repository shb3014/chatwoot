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
    base_content = I18n.with_locale(account.locale) do
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
    base_content = I18n.with_locale(account.locale) do
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

    Llm::TranslationService.new(conversation).translate_message(message)
  rescue StandardError => e
    Rails.logger.error "[EmailCollect] Translation failed: #{e.message}"
    message
  end
end

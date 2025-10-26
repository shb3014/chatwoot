class Llm::TranslationService < Llm::BaseOpenAiService
  def initialize(conversation)
    super()
    @conversation = conversation
  end

  def translate_message(message, target_language: nil)
    return message if message.blank?

    target_language ||= determine_target_language
    return message unless target_language

    Rails.logger.info "[TranslationService] Translating message to #{target_language}"
    Rails.logger.debug "[TranslationService] Original message: #{message[0..100]}..." if message.length > 100

    response = @client.chat(parameters: translation_parameters(message, target_language))
    translated = parse_translation_response(response, message)

    Rails.logger.info "[TranslationService] Translation successful"
    Rails.logger.debug "[TranslationService] Translated message: #{translated[0..100]}..." if translated.length > 100

    translated
  rescue StandardError => e
    Rails.logger.error "[TranslationService] Translation failed: #{e.message}"
    Rails.logger.error "[TranslationService] Backtrace: #{e.backtrace.first(5).join("\n")}"
    message # Return original message if translation fails
  end

  private

  def determine_target_language
    # Priority: conversation language > account locale
    conversation_language = @conversation.language
    account_locale = @conversation.account.locale_english_name

    Rails.logger.info "[TranslationService] Determining target language for conversation #{@conversation.id}"
    Rails.logger.info "[TranslationService] Conversation language: #{conversation_language.inspect}"
    Rails.logger.info "[TranslationService] Account locale: #{account_locale.inspect}"

    if conversation_language.present?
      Rails.logger.info "[TranslationService] Using conversation language: #{conversation_language}"
      return conversation_language
    end

    Rails.logger.info "[TranslationService] Using account locale: #{account_locale}"
    account_locale
  end

  def translation_parameters(message, target_language)
    {
      model: @model,
      messages: [
        {
          role: 'system',
          content: "You are a translation assistant. Translate the following message to #{target_language}. Return only the translated text without any explanations or additional text."
        },
        {
          role: 'user',
          content: message
        }
      ]
    }
  end

  def parse_translation_response(response, original_message)
    response.dig('choices', 0, 'message', 'content')&.strip || original_message
  end
end


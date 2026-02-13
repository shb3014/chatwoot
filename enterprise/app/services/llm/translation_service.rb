class Llm::TranslationService < Llm::BaseOpenAiService
  def initialize(conversation = nil)
    super(model_type: :fast)
    @conversation = conversation
  end

  def translate_message(message, target_language: nil)
    return message if message.blank?

    target_language ||= determine_target_language
    return message unless target_language

    response = @client.chat(parameters: translation_parameters(message, target_language))
    parse_translation_response(response, message)

  rescue StandardError => e
    Rails.logger.error "[TranslationService] Translation failed: #{e.message}"
    Rails.logger.error "[TranslationService] Backtrace: #{e.backtrace.first(5).join("\n")}"
    message # Return original message if translation fails
  end

  private

  def determine_target_language
    # Priority: conversation language > account locale > auto-detect from conversation
    conversation_language = @conversation.language
    account_locale = @conversation.account.locale_english_name

    if conversation_language.present?
      Rails.logger.info "[TranslationService] Using conversation language: #{conversation_language}"
      return conversation_language
    end

    return account_locale if account_locale.present? && account_locale.downcase != 'english'

    # Auto-detect language from conversation history
    detect_language_from_conversation
  end

  def detect_language_from_conversation
    recent_messages = @conversation.messages
                                   .where(message_type: :incoming)
                                   .where(private: false)
                                   .order(created_at: :desc)
                                   .limit(5)
                                   .pluck(:content)
                                   .reject(&:blank?)

    return nil if recent_messages.empty?

    response = @client.chat(
      parameters: {
        model: @model,
        messages: [
          {
            role: 'system',
            content: 'You are a language detection assistant. Analyze the provided conversation messages and identify the primary language used by the user. Return ONLY the language name in English (e.g., "Chinese", "Spanish", "French", "English"). If you cannot determine the language, return "English".'
          },
          {
            role: 'user',
            content: "Detect the language from these messages:\n\n#{recent_messages.join("\n\n")}"
          }
        ]
      }
    )

    detected = response.dig('choices', 0, 'message', 'content')&.strip
    detected.presence
  rescue StandardError => e
    Rails.logger.error "[TranslationService] Language detection failed: #{e.message}"
    nil
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

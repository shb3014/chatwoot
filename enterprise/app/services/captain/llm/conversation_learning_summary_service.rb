class Captain::Llm::ConversationLearningSummaryService < Llm::BaseOpenAiService
  def initialize(conversation)
    super()
    @conversation = conversation
    @content = build_conversation_text
  end

  def summarize
    response = @client.chat(parameters: chat_parameters)
    parse_response(response)
  rescue OpenAI::Error => e
    Rails.logger.error "OpenAI API Error: #{e.message}"
    nil
  end

  private

  attr_reader :conversation, :content

  def chat_parameters
    account_language = conversation.account.locale_english_name
    prompt = Captain::Llm::SystemPromptsService.conversation_learning_summary(account_language)

    {
      model: @model,
      response_format: { type: 'json_object' },
      messages: [
        {
          role: 'system',
          content: prompt
        },
        {
          role: 'user',
          content: content
        }
      ]
    }
  end

  def parse_response(response)
    content = response.dig('choices', 0, 'message', 'content')
    return nil if content.nil?

    parsed = JSON.parse(content.strip)
    parsed['rejected'] = parse_rejected(parsed['rejected'])
    parsed['rejection_reason'] = normalize_rejection_reason(parsed['rejection_reason'])
    parsed['quality_rating'] = normalize_rating(parsed['quality_rating'])
    parsed
  rescue JSON::ParserError => e
    Rails.logger.error "Error parsing conversation learning summary: #{e.message}"
    nil
  end

  def build_conversation_text
    messages = conversation
               .messages
               .where(message_type: [:incoming, :outgoing])
               .where(private: false)
               .reorder(created_at: :asc)

    message_lines = messages.filter_map do |message|
      content = message.content.to_s.strip
      next if content.blank?

      "#{message_role(message)}: #{content}"
    end

    channel_name = conversation.inbox&.channel&.name || conversation.inbox&.channel_type || 'Unknown'

    [
      "Conversation ID: ##{conversation.display_id}",
      "Channel: #{channel_name}",
      'Message History:',
      message_lines.join("\n")
    ].join("\n")
  end

  def message_role(message)
    return 'Customer' if message.incoming?

    sender_type = message.sender_type.to_s
    return 'Captain' if ['AgentBot', 'Captain::Assistant'].include?(sender_type)

    return 'Human agent' if sender_type == 'User' && message.sender.is_a?(User)

    'Support'
  end

  def normalize_rating(value)
    rating = value.to_i
    return nil if rating.negative?

    [[rating, 100].min, 0].max
  end

  def parse_rejected(value)
    return true if value == true || value.to_s.casecmp('true').zero?

    false
  end

  def normalize_rejection_reason(value)
    return nil if value.blank?

    value.to_s.strip
  end
end

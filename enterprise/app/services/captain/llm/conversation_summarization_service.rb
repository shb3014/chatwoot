class Captain::Llm::ConversationSummarizationService < Llm::BaseOpenAiService
  def initialize(conversation)
    super()
    @conversation = conversation
    @account = conversation.account
    @transcript = build_conversation_transcript
    @labels_context = build_labels_context
  end

  def generate
    return nil if @transcript.blank?

    response = @client.chat(parameters: chat_parameters)
    result = parse_response(response)
    return nil unless result

    persist_summary(result)
    assign_labels(result['labels']) if result['labels'].present?

    result
  rescue OpenAI::Error => e
    Rails.logger.error "Captain::Llm::ConversationSummarizationService OpenAI API Error: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "Captain::Llm::ConversationSummarizationService Error: #{e.message}"
    nil
  end

  private

  attr_reader :conversation, :account, :transcript, :labels_context

  def chat_parameters
    account_language = account.locale_english_name
    prompt = Captain::Llm::SystemPromptsService.conversation_summarization(account_language, @labels_context)

    {
      model: @model,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: prompt },
        { role: 'user', content: transcript }
      ]
    }
  end

  def parse_response(response)
    content = response.dig('choices', 0, 'message', 'content')
    return nil if content.nil?

    parsed = JSON.parse(content.strip)
    {
      'summary' => parsed['summary'].to_s.strip,
      'labels' => Array(parsed['labels']).map(&:to_s).map(&:strip).reject(&:blank?)
    }
  rescue JSON::ParserError => e
    Rails.logger.error "Captain::Llm::ConversationSummarizationService parse error: #{e.message}"
    nil
  end

  def persist_summary(result)
    summary_data = {
      'content' => result['summary'],
      'labels' => result['labels'],
      'generated_at' => Time.current.iso8601
    }

    conversation.update!(captain_summary: summary_data)
  end

  def assign_labels(label_titles)
    return if label_titles.blank?

    # Only assign labels that actually exist in the account
    existing_labels = account.labels.where('LOWER(title) IN (?)', label_titles.map(&:downcase))
    return if existing_labels.empty?

    existing_label_titles = existing_labels.pluck(:title)
    conversation.add_labels(existing_label_titles)
  rescue StandardError => e
    Rails.logger.error "Captain::Llm::ConversationSummarizationService label assignment error: #{e.message}"
  end

  def build_conversation_transcript
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

    return nil if message_lines.empty?

    channel_name = conversation.inbox&.channel&.name || conversation.inbox&.channel_type || 'Unknown'

    [
      "Conversation ID: ##{conversation.display_id}",
      "Channel: #{channel_name}",
      "Status: #{conversation.status}",
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

  def build_labels_context
    labels_with_ai_learning = account.labels.where.not(ai_learning_description: [nil, ''])
    return '' if labels_with_ai_learning.empty?

    lines = labels_with_ai_learning.map do |label|
      "- \"#{label.title}\": #{label.ai_learning_description}"
    end

    lines.join("\n")
  end
end

class Captain::Llm::ConversationSummarizationService < Llm::BaseOpenAiService
  def initialize(conversation)
    super(model_type: :fast)
    @conversation = conversation
    @account = conversation.account
    @transcript = build_conversation_transcript
    @labels_context = build_labels_context
  end

  def generate
    return nil if @transcript.blank?

    hard_rule_labels = Labels::HardRuleMatchService.new(conversation).perform
    @hard_rule_exclusive = resolve_exclusive_from_hard_rules(hard_rule_labels)

    response = @client.chat(parameters: chat_parameters)
    result = parse_response(response)
    return nil unless result

    old_ai_labels = conversation.captain_summary&.dig('labels') || []

    llm_labels = @hard_rule_exclusive ? [] : (result['labels'] || [])
    final_labels = reassign_labels(llm_labels, old_ai_labels, hard_rule_labels)

    result['labels'] = final_labels || []
    persist_summary(result)

    result
  rescue OpenAI::Error => e
    captain_logger.error "[Captain::Summarization] OpenAI API Error: #{e.message}"
    nil
  rescue StandardError => e
    captain_logger.error "[Captain::Summarization] Error: #{e.message}"
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

  def resolve_exclusive_from_hard_rules(hard_rule_labels)
    return nil if hard_rule_labels.blank?

    account.labels
           .where(exclusive: true)
           .where('LOWER(title) IN (?)', hard_rule_labels.map(&:downcase))
           .order(:position, :title)
           .pick(:title)
  end

  def reassign_labels(new_label_titles, old_ai_labels, hard_rule_labels = [])
    if hard_rule_labels.blank? && conversation.has_exclusive_label?
      existing = conversation.label_list.map(&:to_s)
      exclusive_label = account.labels.where(exclusive: true)
                               .where('LOWER(title) IN (?)', existing.map(&:downcase))
                               .order(:position, :title)
                               .pick(:title)
      if exclusive_label && existing.size > 1
        cleaned = [exclusive_label]
        conversation.update!(label_list: cleaned)
        return cleaned
      end
      return existing
    end

    current_labels = conversation.label_list.map(&:to_s)

    stale_labels = old_ai_labels.map(&:downcase) - new_label_titles.map(&:downcase)
    current_labels = current_labels.reject { |l| stale_labels.include?(l.downcase) } if stale_labels.present?

    valid_new_labels = if new_label_titles.present?
                         account.labels.where('LOWER(title) IN (?)', new_label_titles.map(&:downcase)).pluck(:title)
                       else
                         []
                       end

    valid_hard_rule_labels = if hard_rule_labels.present?
                               account.labels.where('LOWER(title) IN (?)', hard_rule_labels.map(&:downcase)).pluck(:title)
                             else
                               []
                             end

    combined_labels = (current_labels + valid_hard_rule_labels + valid_new_labels).uniq

    exclusive_label = account.labels.where(exclusive: true)
                             .where('LOWER(title) IN (?)', combined_labels.map(&:downcase))
                             .order(:position, :title)
                             .pick(:title)
    combined_labels = [exclusive_label] if exclusive_label.present?

    conversation.update!(label_list: combined_labels)
    combined_labels
  rescue StandardError => e
    captain_logger.error "[Captain::Summarization] Label reassignment error: #{e.message}"
    nil
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

    email_context_lines = build_email_context_lines
    return nil if message_lines.empty? && email_context_lines.empty?

    channel_name = conversation.inbox&.channel&.name || conversation.inbox&.channel_type || 'Unknown'

    transcript_lines = [
      "Conversation ID: ##{conversation.display_id}",
      "Channel: #{channel_name}",
      "Status: #{conversation.status}"
    ]

    transcript_lines.concat(email_context_lines) if email_context_lines.present?
    transcript_lines << 'Message History:'
    transcript_lines << (message_lines.present? ? message_lines.join("\n") : '(No non-empty message body)')

    transcript_lines.join("\n")
  end

  def message_role(message)
    return 'Customer' if message.incoming?

    sender_type = message.sender_type.to_s
    return 'Captain' if ['AgentBot', 'Captain::Assistant'].include?(sender_type)
    return 'Human agent' if sender_type == 'User' && message.sender.is_a?(User)

    'Support'
  end

  def build_labels_context
    labels_with_ai_learning = account.labels.reorder(:position, :title).where.not(ai_learning_description: [nil, ''])
    return '' if labels_with_ai_learning.empty?

    lines = labels_with_ai_learning.map do |label|
      "- \"#{label.title}\": #{label.ai_learning_description}"
    end

    lines.join("\n")
  end

  def build_email_context_lines
    return [] unless conversation.inbox&.email?

    lines = []
    customer_email = conversation.contact&.email.to_s.strip.presence || latest_incoming_from_email_header
    subject = conversation.additional_attributes&.dig('mail_subject').to_s.strip

    lines << "Customer Email: #{customer_email}" if customer_email.present?
    lines << "Mail Subject: #{subject}" if subject.present?
    lines
  end

  def latest_incoming_from_email_header
    latest_email_message = conversation.messages.where(message_type: :incoming).where(private: false).reorder(created_at: :desc).first
    from_values = latest_email_message&.content_attributes&.dig('email', 'from')

    Array(from_values).map { |value| value.to_s.strip }.find(&:present?)
  end
end

class Labels::HardRuleMatchService
  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
  end

  def perform
    labels_with_rules = @account.labels
                                .where.not(hard_rules: [nil, []])
                                .order(:position, :title)

    return [] if labels_with_rules.empty?

    message_contents = fetch_message_contents
    matched = labels_with_rules.select { |label| rules_match?(label.hard_rules, message_contents) }
    matched.map(&:title)
  end

  private

  def fetch_message_contents
    @conversation
      .messages
      .where(message_type: :incoming)
      .where(private: false)
      .pluck(:content)
      .compact
      .map(&:strip)
      .reject(&:blank?)
  end

  def rules_match?(rules, message_contents)
    return false if rules.blank?

    results = rules.map { |rule| evaluate_single_rule(rule, message_contents) }

    combined = results.first
    rules.each_with_index do |_rule, idx|
      next if idx.zero?

      operator = rules[idx - 1]['query_operator']&.upcase
      combined = if operator == 'OR'
                   combined || results[idx]
                 else
                   combined && results[idx]
                 end
    end

    combined
  end

  def evaluate_single_rule(rule, message_contents)
    key = rule['attribute_key']
    operator = rule['filter_operator']
    values = Array(rule['values']).map(&:to_s)

    case key
    when 'content'
      evaluate_content(operator, values, message_contents)
    when 'mail_subject'
      evaluate_text_attribute(operator, values, mail_subject)
    when 'email'
      evaluate_text_attribute(operator, values, contact_email)
    when 'inbox_id'
      evaluate_id_attribute(operator, values, @conversation.inbox_id)
    else
      false
    end
  end

  def evaluate_content(operator, values, message_contents)
    combined_content = message_contents.join(' ')

    case operator
    when 'contains'
      values.any? { |v| combined_content.downcase.include?(v.downcase) }
    when 'does_not_contain'
      values.none? { |v| combined_content.downcase.include?(v.downcase) }
    when 'equal_to'
      values.any? { |v| message_contents.any? { |mc| mc.casecmp(v).zero? } }
    when 'not_equal_to'
      values.none? { |v| message_contents.any? { |mc| mc.casecmp(v).zero? } }
    when 'is_present'
      message_contents.any?
    when 'is_not_present'
      message_contents.empty?
    else
      false
    end
  end

  def evaluate_text_attribute(operator, values, attribute_value)
    case operator
    when 'contains'
      return false if attribute_value.blank?

      values.any? { |v| attribute_value.downcase.include?(v.downcase) }
    when 'does_not_contain'
      return true if attribute_value.blank?

      values.none? { |v| attribute_value.downcase.include?(v.downcase) }
    when 'equal_to'
      return false if attribute_value.blank?

      values.any? { |v| attribute_value.casecmp(v).zero? }
    when 'not_equal_to'
      return true if attribute_value.blank?

      values.none? { |v| attribute_value.casecmp(v).zero? }
    when 'is_present'
      attribute_value.present?
    when 'is_not_present'
      attribute_value.blank?
    else
      false
    end
  end

  def evaluate_id_attribute(operator, values, attribute_value)
    str_value = attribute_value.to_s

    case operator
    when 'equal_to'
      values.include?(str_value)
    when 'not_equal_to'
      values.exclude?(str_value)
    when 'is_present'
      attribute_value.present?
    when 'is_not_present'
      attribute_value.blank?
    else
      false
    end
  end

  def mail_subject
    @conversation.additional_attributes&.dig('mail_subject').to_s
  end

  def contact_email
    @conversation.contact&.email.to_s
  end
end

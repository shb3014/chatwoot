# == Schema Information
#
# Table name: labels
#
#  id                      :bigint           not null, primary key
#  ai_learning_description :text
#  color                   :string           default("#1f93ff"), not null
#  description             :text
#  exclusive               :boolean          default(FALSE), not null
#  hard_rules              :jsonb            not null
#  position                :integer          default(0), not null
#  show_on_sidebar         :boolean
#  title                   :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint
#
# Indexes
#
#  index_labels_on_account_id            (account_id)
#  index_labels_on_title_and_account_id  (title,account_id) UNIQUE
#
class Label < ApplicationRecord
  include RegexHelper
  include AccountCacheRevalidator

  belongs_to :account

  validates :title,
            presence: { message: I18n.t('errors.validations.presence') },
            format: { with: UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE },
            uniqueness: { scope: :account_id }

  validate :validate_hard_rules_format

  after_update_commit :update_associated_models
  default_scope { order(:position, :title) }

  HARD_RULE_ATTRIBUTE_KEYS = %w[content mail_subject email inbox_id].freeze
  HARD_RULE_FILTER_OPERATORS = %w[equal_to not_equal_to contains does_not_contain is_present is_not_present].freeze

  before_validation do
    self.title = title.downcase if attribute_present?('title')
  end

  def has_hard_rules?
    hard_rules.present? && hard_rules.is_a?(Array) && hard_rules.any?
  end

  def conversations
    account.conversations.tagged_with(title)
  end

  def messages
    account.messages.where(conversation_id: conversations.pluck(:id))
  end

  def reporting_events
    account.reporting_events.where(conversation_id: conversations.pluck(:id))
  end

  private

  def update_associated_models
    return unless title_previously_changed?

    Labels::UpdateJob.perform_later(title, title_previously_was, account_id)
  end

  def validate_hard_rules_format
    return if hard_rules.blank?
    return errors.add(:hard_rules, 'must be an array') unless hard_rules.is_a?(Array)

    hard_rules.each_with_index do |rule, idx|
      unless rule.is_a?(Hash)
        errors.add(:hard_rules, "rule ##{idx + 1} must be a hash")
        next
      end

      unless rule['attribute_key'].in?(HARD_RULE_ATTRIBUTE_KEYS)
        errors.add(:hard_rules, "rule ##{idx + 1} has invalid attribute_key '#{rule['attribute_key']}'")
      end

      unless rule['filter_operator'].in?(HARD_RULE_FILTER_OPERATORS)
        errors.add(:hard_rules, "rule ##{idx + 1} has invalid filter_operator '#{rule['filter_operator']}'")
      end
    end
  end
end

module Enterprise::Concerns::Conversation
  extend ActiveSupport::Concern

  included do
    belongs_to :sla_policy, optional: true
    has_one :applied_sla, dependent: :destroy_async
    has_many :sla_events, dependent: :destroy_async
    has_many :captain_responses, class_name: 'Captain::AssistantResponse', dependent: :nullify, as: :documentable
    has_one :captain_conversation_learning, class_name: 'Captain::ConversationLearning', dependent: :destroy_async
    before_validation :validate_sla_policy, if: -> { sla_policy_id_changed? }
    around_save :ensure_applied_sla_is_created, if: -> { sla_policy_id_changed? }
    after_create_commit :schedule_deferred_summarization
  end

  def captain_learning_eligible?
    captain_messages.exists? && human_agent_messages.exists?
  end

  private

  # Emails are complete messages on arrival, so summarize immediately.
  # Live chat conversations develop over time, so defer summarization.
  def schedule_deferred_summarization
    return if resolved?

    if inbox.email?
      Captain::ConversationSummarizationJob.perform_later(self)
    else
      Captain::ConversationSummarizationJob.set(wait: 1.hour).perform_later(self)
    end
  end

  def captain_messages
    messages.where(sender_type: ['AgentBot', 'Captain::Assistant'])
  end

  def human_agent_messages
    messages.where(message_type: :outgoing, sender_type: 'User')
  end

  def validate_sla_policy
    # TODO: remove these validations once we figure out how to deal with these cases
    if sla_policy_id.nil? && changes[:sla_policy_id].first.present?
      errors.add(:sla_policy, 'cannot remove sla policy from conversation')
      return
    end

    if changes[:sla_policy_id].first.present?
      errors.add(:sla_policy, 'conversation already has a different sla')
      return
    end

    errors.add(:sla_policy, 'sla policy account mismatch') if sla_policy&.account_id != account_id
  end

  # handling inside a transaction to ensure applied sla record is also created
  def ensure_applied_sla_is_created
    ActiveRecord::Base.transaction do
      yield
      create_applied_sla(sla_policy_id: sla_policy_id) if applied_sla.blank?
    end
  rescue ActiveRecord::RecordInvalid
    raise ActiveRecord::Rollback
  end
end

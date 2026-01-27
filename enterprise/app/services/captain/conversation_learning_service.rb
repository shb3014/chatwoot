module Captain
  class ConversationLearningService
    def initialize(conversation)
      @conversation = conversation
      @assistant = conversation.inbox.captain_assistant
    end

    def enqueue_learning(force: false)
      unless eligible_for_learning?
        Captain::Logger.info('[ConversationLearning] Skipped (ineligible)', conversation_id: @conversation.id)
        return
      end
      if skip_learning?(force: force)
        Captain::Logger.info('[ConversationLearning] Skipped (up-to-date)', conversation_id: @conversation.id)
        return
      end

      Captain::Conversation::LearningJob.perform_later(@conversation.id, force: force)
    end

    def learn!(force: false)
      return unless eligible_for_learning?
      return if skip_learning?(force: force)

      summary = Captain::Llm::ConversationLearningSummaryService.new(@conversation).summarize
      return if summary.blank?

      learning = learning_record || build_learning_record
      if summary['rejected']
        rejection_reason = summary['rejection_reason'].presence || 'Rejected by LLM: insufficient signal to learn.'
        learning.assign_attributes(
          status: :rejected,
          rejection_reason: rejection_reason,
          rejected_at: Time.current,
          issue_summary: nil,
          resolution_summary: nil,
          quality_rating: nil,
          learned_at: nil,
          embedding: nil,
          last_message_at: latest_message_at
        )
      else
        learning.assign_attributes(
          issue_summary: summary['issue_summary'],
          resolution_summary: summary['resolution_summary'],
          quality_rating: summary['quality_rating'],
          status: :learned,
          learned_at: Time.current,
          rejected_at: nil,
          rejection_reason: nil,
          last_message_at: latest_message_at
        )
      end
      learning.save!
      @conversation.touch(:updated_at)
      @conversation.dispatch_conversation_updated_event
      learning
    end

    private

    def learning_record
      @learning_record ||= Captain::ConversationLearning.find_by(conversation: @conversation)
    end

    def build_learning_record
      Captain::ConversationLearning.new(conversation: @conversation, account: @conversation.account, assistant: @assistant)
    end

    def eligible_for_learning?
      @assistant.present? && @conversation.captain_learning_eligible?
    end

    def skip_learning?(force: false)
      return false if force
      return false unless learning_record
      return true if learning_record.forgotten?

      (learning_record.learned? || learning_record.rejected?) && up_to_date?
    end

    def up_to_date?
      return false if learning_record.last_message_at.blank?

      learning_record.last_message_at >= latest_message_at
    end

    def latest_message_at
      @latest_message_at ||= @conversation.messages
                                          .where(message_type: [:incoming, :outgoing])
                                          .order(created_at: :desc)
                                          .limit(1)
                                          .pick(:created_at) || @conversation.updated_at
    end
  end
end

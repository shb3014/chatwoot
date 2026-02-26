class Captain::ConversationSummarizationJob < ApplicationJob
  queue_as :low

  # @param force [Boolean] when true, skip freshness and exclusive-label checks
  #   (used for manual re-summarize and email channel refreshes)
  def perform(conversation, force: false)
    unless force
      # Conversations carrying an exclusive label are considered fully classified;
      # skip auto-summarization to avoid overriding that classification.
      return if conversation.has_exclusive_label?

      existing_summary = conversation.captain_summary
      if existing_summary.present? && existing_summary['generated_at'].present?
        generated_at = begin
          Time.parse(existing_summary['generated_at'])
        rescue StandardError
          nil
        end
        return if generated_at && generated_at > 1.hour.ago
      end
    end

    Rails.logger.info("#{self.class.name} Generating summary for conversation_id=#{conversation.id}")
    Captain::Llm::ConversationSummarizationService.new(conversation).generate
  end
end

class Captain::ConversationSummarizationJob < ApplicationJob
  queue_as :low

  def perform(conversation)
    # Skip if summary already exists and is recent (within last hour)
    existing_summary = conversation.captain_summary
    if existing_summary.present? && existing_summary['generated_at'].present?
      generated_at = begin
        Time.parse(existing_summary['generated_at'])
      rescue StandardError
        nil
      end
      return if generated_at && generated_at > 1.hour.ago
    end

    Rails.logger.info("#{self.class.name} Generating summary for conversation_id=#{conversation.id}")
    Captain::Llm::ConversationSummarizationService.new(conversation).generate
  end
end

class Captain::Conversation::LearningJob < ApplicationJob
  queue_as :low

  def perform(conversation_id, force: false)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    Captain::ConversationLearningService.new(conversation).learn!(force: force)
  end
end

module Enterprise::Message
  private

  # Extends the base message callback to trigger immediate summarization
  # for incoming email messages (handles replies in existing conversations).
  def execute_after_create_commit_callbacks
    super
    trigger_email_summarization
  end

  # Email replies into existing conversations bypass the conversation-creation
  # callback, so we trigger summarization here with force: true to ensure the
  # summary is refreshed with the new email content.
  def trigger_email_summarization
    return unless incoming?
    return unless inbox.email?

    Captain::ConversationSummarizationJob.perform_later(conversation, force: true)
  end
end

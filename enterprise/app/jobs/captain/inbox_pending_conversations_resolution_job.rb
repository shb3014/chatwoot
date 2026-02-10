class Captain::InboxPendingConversationsResolutionJob < ApplicationJob
  queue_as :low

  def perform(inbox)
    return unless captain_pending_auto_resolve_enabled?

    Current.executed_by = inbox.captain_assistant

    resolvable_conversations = inbox.conversations.pending.where('last_activity_at < ? ', Time.now.utc - 1.hour).limit(Limits::BULK_ACTIONS_LIMIT)
    resolvable_conversations.each do |conversation|
      create_outgoing_message(conversation, inbox)
      # Trigger summarization alongside auto-resolution
      Captain::ConversationSummarizationJob.perform_later(conversation)
      conversation.resolved!
    end
  ensure
    Current.reset
  end

  private

  def captain_pending_auto_resolve_enabled?
    GlobalConfigService.load('CAPTAIN_PENDING_AUTO_RESOLVE_ENABLED', 'true') == 'true'
  end

  def create_outgoing_message(conversation, inbox)
    I18n.with_locale(inbox.account.locale) do
      base_message = inbox.captain_assistant.config['resolution_message'].presence || I18n.t('conversations.activity.auto_resolution_message')

      translated_message = Llm::TranslationService.new(conversation).translate_message(base_message)

      conversation.messages.create!(
        {
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          content: translated_message,
          sender: inbox.captain_assistant
        }
      )
    end
  end
end

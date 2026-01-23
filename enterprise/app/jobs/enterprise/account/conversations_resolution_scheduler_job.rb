module Enterprise::Account::ConversationsResolutionSchedulerJob
  def perform
    super

    resolve_captain_conversations
  end

  private

  def captain_pending_auto_resolve_enabled?
    GlobalConfigService.load('CAPTAIN_PENDING_AUTO_RESOLVE_ENABLED', 'true') == 'true'
  end

  def resolve_captain_conversations
    return unless captain_pending_auto_resolve_enabled?

    CaptainInbox.all.find_each(batch_size: 100) do |captain_inbox|
      inbox = captain_inbox.inbox

      next if inbox.email?

      Captain::InboxPendingConversationsResolutionJob.perform_later(
        inbox
      )
    end
  end
end

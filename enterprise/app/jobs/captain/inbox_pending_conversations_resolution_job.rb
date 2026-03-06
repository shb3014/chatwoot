class Captain::InboxPendingConversationsResolutionJob < ApplicationJob
  queue_as :low

  def perform(_inbox)
    # Intentionally disabled: Captain pending auto-resolution is turned off globally.
    nil
  end
end

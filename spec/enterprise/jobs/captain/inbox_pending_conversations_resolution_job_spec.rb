require 'rails_helper'

RSpec.describe Captain::InboxPendingConversationsResolutionJob, type: :job do
  let!(:inbox) { create(:inbox) }
  let!(:resolvable_pending_conversation) { create(:conversation, inbox: inbox, last_activity_at: 2.hours.ago, status: :pending) }
  let!(:captain_assistant) { create(:captain_assistant, account: inbox.account) }
  let!(:captain_inbox) { create(:captain_inbox, inbox: inbox, captain_assistant: captain_assistant) }

  it 'queues the job' do
    expect { described_class.perform_later(inbox) }
      .to have_enqueued_job.on_queue('low')
  end

  it 'does not resolve pending conversations when feature is disabled' do
    described_class.perform_now(inbox)

    expect(resolvable_pending_conversation.reload.status).to eq('pending')
    expect(resolvable_pending_conversation.messages.outgoing.count).to eq(0)
  end
end

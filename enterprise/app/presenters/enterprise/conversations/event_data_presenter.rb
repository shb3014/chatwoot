module Enterprise::Conversations::EventDataPresenter
  def push_data
    data = if account.feature_enabled?('sla')
             super.merge(
               applied_sla: applied_sla&.push_event_data,
               sla_events: sla_events.map(&:push_event_data),
               sla_policy_id: sla_policy_id
             )
           else
             super
           end

    data.merge(captain_learning_payload)
  end

  private

  def captain_learning_payload
    return {} unless respond_to?(:captain_learning_eligible?)

    learning = respond_to?(:captain_conversation_learning) ? captain_conversation_learning : nil
    {
      captain_learning_eligible: captain_learning_eligible?,
      captain_learning: if learning
                          {
                            id: learning.id,
                            status: learning.status,
                            issue_summary: learning.issue_summary,
                            resolution_summary: learning.resolution_summary,
                            quality_rating: learning.quality_rating,
                            rejection_reason: learning.rejection_reason,
                            rejected_at: learning.rejected_at&.to_i,
                            learned_at: learning.learned_at&.to_i,
                            last_message_at: learning.last_message_at&.to_i,
                            created_at: learning.created_at.to_i,
                            updated_at: learning.updated_at.to_i
                          }
                        end
    }
  end
end

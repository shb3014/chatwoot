if conversation.account.feature_enabled?('sla')
  json.applied_sla do
    json.partial! 'api/v1/models/applied_sla', formats: [:json], resource: conversation.applied_sla if conversation.applied_sla.present?
  end
  json.sla_events do
    json.array! conversation.sla_events do |sla_event|
      json.partial! 'api/v1/models/sla_event', formats: [:json], sla_event: sla_event
    end
  end
end

# Captain state tracking
json.captain_state conversation.captain_state
json.captain_last_action_at conversation.captain_last_action_at&.to_i
json.captain_handed_off_at conversation.captain_handed_off_at&.to_i
json.captain_handed_off_by_id conversation.captain_handed_off_by_id

json.captain_learning_eligible conversation.captain_learning_eligible?
if conversation.captain_conversation_learning.present?
  json.captain_learning do
    json.partial! 'api/v1/models/captain/learned_conversation',
                  formats: [:json],
                  resource: conversation.captain_conversation_learning
  end
else
  json.captain_learning nil
end

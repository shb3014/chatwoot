# TODO: Move this into models jbuilder
# Currently the file there is used only for search endpoint.
# Everywhere else we use conversation builder in partials folder

json.meta do
  json.sender do
    json.partial! 'api/v1/models/contact', formats: [:json], resource: conversation.contact
  end
  json.channel conversation.inbox.try(:channel_type)
  if conversation.assignee&.account
    json.assignee do
      json.partial! 'api/v1/models/agent', formats: [:json], resource: conversation.assignee
    end
  end
  if conversation.team.present?
    json.team do
      json.partial! 'api/v1/models/team', formats: [:json], resource: conversation.team
    end
  end
  json.hmac_verified conversation.contact_inbox&.hmac_verified
end

json.id conversation.display_id
last_msg = conversation.cached_latest_message
if last_msg.blank?
  json.messages []
else
  json.messages [last_msg.push_event_data]
end

json.account_id conversation.account_id
json.uuid conversation.uuid
json.additional_attributes conversation.additional_attributes
json.agent_last_seen_at conversation.agent_last_seen_at.to_i
json.assignee_last_seen_at conversation.assignee_last_seen_at.to_i
json.can_reply conversation.can_reply?
json.contact_last_seen_at conversation.contact_last_seen_at.to_i
json.custom_attributes conversation.custom_attributes
json.inbox_id conversation.inbox_id
json.labels conversation.cached_label_list_array
json.muted conversation.muted?
json.snoozed_until conversation.snoozed_until
json.status conversation.status
json.captain_state conversation.captain_state
json.captain_last_action_at conversation.captain_last_action_at&.to_i
json.captain_handed_off_at conversation.captain_handed_off_at&.to_i
json.captain_handed_off_by_id conversation.captain_handed_off_by_id
json.created_at conversation.created_at.to_i
json.updated_at conversation.updated_at.to_f
json.timestamp conversation.last_activity_at.to_i
json.first_reply_created_at conversation.first_reply_created_at.to_i
json.unread_count conversation.cached_unread_count
json.last_non_activity_message conversation.cached_latest_non_activity_message.try(:push_event_data)
json.last_activity_at conversation.last_activity_at.to_i
json.priority conversation.priority
json.waiting_since conversation.waiting_since.to_i.to_i
json.sla_policy_id conversation.sla_policy_id

if conversation.respond_to?(:captain_learning_eligible?)
  json.captain_learning_eligible conversation.captain_learning_eligible?
  if conversation.respond_to?(:captain_conversation_learning) && conversation.captain_conversation_learning.present?
    json.captain_learning do
      json.partial! 'api/v1/models/captain/learned_conversation',
                    formats: [:json],
                    resource: conversation.captain_conversation_learning
    end
  else
    json.captain_learning nil
  end
end
json.partial! 'enterprise/api/v1/conversations/partials/conversation', conversation: conversation if ChatwootApp.enterprise?

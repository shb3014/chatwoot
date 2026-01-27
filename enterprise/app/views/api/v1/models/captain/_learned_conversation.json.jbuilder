json.id resource.id
json.status resource.status
json.issue_summary resource.issue_summary
json.resolution_summary resource.resolution_summary
json.quality_rating resource.quality_rating
json.learned_at resource.learned_at&.to_i
json.last_message_at resource.last_message_at&.to_i
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i

if resource.assistant
  json.assistant do
    json.partial! 'api/v1/models/captain/assistant', formats: [:json], resource: resource.assistant
  end
end

if resource.conversation
  json.conversation do
    json.id resource.conversation.display_id
    json.display_id resource.conversation.display_id
    json.status resource.conversation.status
    json.inbox_id resource.conversation.inbox_id
  end
end

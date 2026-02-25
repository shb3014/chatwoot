json.meta do
  json.mine_count @conversations_count[:mine_count]
  json.assigned_count @conversations_count[:assigned_count]
  json.unassigned_count @conversations_count[:unassigned_count]
  json.all_count @conversations_count[:all_count]
  json.unresolved_count @conversations_count[:unresolved_count]
  json.unread_count @conversations_count[:unread_count]
end

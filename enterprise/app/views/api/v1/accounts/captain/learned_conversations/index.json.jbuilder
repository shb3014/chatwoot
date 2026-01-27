json.payload do
  json.array! @learned_conversations do |learning|
    json.partial! 'api/v1/models/captain/learned_conversation', formats: [:json], resource: learning
  end
end

json.meta do
  json.total_count @learned_conversations_count
  json.page @current_page
end

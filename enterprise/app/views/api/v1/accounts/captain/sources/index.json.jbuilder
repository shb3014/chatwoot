json.payload do
  json.array! @sources do |source|
    json.partial! 'api/v1/models/captain/source', formats: [:json], resource: source
  end
end

json.meta do
  json.total_count @sources_count
  json.page @current_page
end

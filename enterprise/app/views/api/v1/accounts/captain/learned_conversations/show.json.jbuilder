json.payload do
  json.partial! 'api/v1/models/captain/learned_conversation', formats: [:json], resource: @learning
end

json.payload do
  json.array! @ai_agents do |ai_agent|
    json.partial! 'api/v1/models/ai_agent', formats: [:json], ai_agent: ai_agent
  end
end
json.meta do
  json.total_count @ai_agents.size
end

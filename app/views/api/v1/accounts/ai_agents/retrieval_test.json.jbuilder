json.context_limit @ai_agent.context_limit
json.context_expansion_radius @ai_agent.context_expansion_radius
json.partial! 'api/v1/models/ai_agent_retrieval', formats: [:json], retrieval: @retrieval
if @web_search
  json.web do
    json.partial! 'api/v1/models/ai_agent_web_search', formats: [:json], web_search: @web_search
  end
end

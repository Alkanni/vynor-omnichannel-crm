json.context_limit @ai_agent.context_limit
json.partial! 'api/v1/models/ai_agent_retrieval', formats: [:json], retrieval: @retrieval

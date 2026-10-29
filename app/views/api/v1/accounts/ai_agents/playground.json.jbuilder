json.messages @reply.messages
json.handoff @reply.handoff
json.labels @reply.labels
json.sheet_row @reply.sheet_row
json.model @ai_agent.model
json.retrieval do
  json.partial! 'api/v1/models/ai_agent_retrieval', formats: [:json], retrieval: @reply.trace.retrieval
end
json.tokens do
  json.input @reply.trace.input_tokens
  json.output @reply.trace.output_tokens
end
json.latency_ms @reply.trace.latency_ms

json.messages @reply.messages
json.handoff @reply.handoff
json.labels @reply.labels
json.sheet_row @reply.sheet_row
json.model @ai_agent.model
json.scope @reply.trace.scope&.to_h&.slice(:decision, :latency_ms)
if @reply.trace.retrieval
  json.retrieval do
    json.partial! 'api/v1/models/ai_agent_retrieval', formats: [:json], retrieval: @reply.trace.retrieval
  end
else
  json.retrieval nil
end
json.tokens do
  json.input @reply.trace.input_tokens
  json.output @reply.trace.output_tokens
end
json.latency_ms @reply.trace.latency_ms

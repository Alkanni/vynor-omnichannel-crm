json.messages @reply.messages
json.handoff @reply.handoff
json.labels @reply.labels
json.sheet_row @reply.sheet_row
json.model @ai_agent.model
json.scope @reply.trace.scope&.to_h&.slice(:decision, :web_query, :web_search_status, :latency_ms, :input_tokens, :output_tokens)
json.validation @reply.trace.validation&.to_h
# Only for a turn that was searched; the scope block says why another turn was not. Ranks are those of the prompt.
if @reply.trace.web_search
  json.web do
    json.query @reply.trace.scope.web_query
    json.partial! 'api/v1/models/ai_agent_web_search', formats: [:json], web_search: @reply.trace.web_search
  end
else
  json.web nil
end
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
  json.cached_input @reply.trace.cached_input_tokens
end
json.latency_ms @reply.trace.latency_ms

json.payload do
  json.array! @knowledge_sources do |knowledge_source|
    json.partial! 'api/v1/models/ai_agent_knowledge_source', formats: [:json], knowledge_source: knowledge_source,
                                                             index_summary: @index_summaries[knowledge_source.id]
  end
end

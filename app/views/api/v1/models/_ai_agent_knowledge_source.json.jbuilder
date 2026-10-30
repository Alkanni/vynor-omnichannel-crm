json.id knowledge_source.id
json.ai_agent_id knowledge_source.ai_agent_id
json.source_type knowledge_source.source_type
json.title knowledge_source.title
json.content knowledge_source.content if knowledge_source.text? || knowledge_source.qa?
json.external_url knowledge_source.external_url if knowledge_source.website?
json.status knowledge_source.status
json.error_message knowledge_source.error_message
json.characters knowledge_source.content.to_s.length
json.truncated knowledge_source.metadata['truncated'] == true
json.created_at knowledge_source.created_at.to_i
json.updated_at knowledge_source.updated_at.to_i
# Lists pass the summaries they loaded in one query; a single source loads its own.
index_summary = local_assigns.fetch(:index_summary) { knowledge_source.index_summary }
json.index do
  json.status index_summary ? index_summary.status_for(knowledge_source) : 'not_indexed'
  json.chunks index_summary&.chunks.to_i
  json.other_model_chunks index_summary&.other_model_chunks.to_i
  json.indexed_at index_summary&.indexed_at&.to_i
end

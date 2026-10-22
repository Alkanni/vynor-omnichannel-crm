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

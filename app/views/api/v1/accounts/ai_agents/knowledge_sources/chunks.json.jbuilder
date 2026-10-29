json.embedding_model @embedding_model
json.payload do
  json.array! @chunks.each.with_index(1).to_a do |(chunk, position)|
    json.id chunk.id
    json.position position
    json.content chunk.content
    json.embedding_model chunk.embedding_model
    json.searchable @searchable_ids.include?(chunk.id)
    json.indexed_at chunk.created_at.to_i
  end
end

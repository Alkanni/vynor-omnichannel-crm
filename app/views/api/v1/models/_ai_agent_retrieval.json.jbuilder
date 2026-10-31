json.mode retrieval.mode
json.embedding_model retrieval.embedding_model
json.queries retrieval.queries
json.chunks retrieval.hits do |hit|
  source = hit.chunk.chunkable
  json.rank hit.rank
  json.score hit.score
  json.distance hit.chunk.try(:neighbor_distance)
  json.content hit.chunk.content
  json.source do
    json.id source.id
    if source.is_a?(AiAgent::Product)
      json.type 'product'
      json.title source.name
    else
      json.type source.source_type
      json.title source.title
    end
  end
end

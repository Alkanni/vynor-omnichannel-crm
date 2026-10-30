# Finds the knowledge chunks an AI Agent sends to the model for a question, up to its Context Limit: the nearest chunks
# by embedding when an embedding model is set, otherwise the chunks sharing the most words with the question
# (see AiAgent::KnowledgeChunk.searchable for the chunks compared). Chunks that are not relevant enough are left out:
# in keyword mode those sharing no word with the question, in vector mode those farther than
# AI_AGENT_EMBEDDING_MAX_DISTANCE when it is set. No chunk at all means the model answers without knowledge.
class AiAgents::KnowledgeRetriever
  # rank starts at 1. score is the cosine distance in vector mode (lower is closer) and the ts_rank in keyword mode
  # (higher is closer).
  Hit = Data.define(:chunk, :rank, :score)
  Result = Data.define(:mode, :embedding_model, :hits)

  pattr_initialize [:ai_agent!, :query!]

  def perform
    embedding_model = AiAgents::LlmClient.embedding_model
    Result.new(mode: embedding_model ? 'vector' : 'keyword', embedding_model: embedding_model, hits: hits(embedding_model))
  end

  private

  def hits(embedding_model)
    chunks = ai_agent.knowledge_chunks.searchable(embedding_model)
    return [] if query.blank? || !chunks.exists?

    relevant = relevance_check(embedding_model)
    candidates(chunks, embedding_model).select { |_chunk, score| relevant.call(score) }.map.with_index(1) do |(chunk, score), rank|
      Hit.new(chunk: chunk, rank: rank, score: score)
    end
  end

  # The top Context Limit chunks with their score, closest first.
  def candidates(chunks, embedding_model)
    return chunks.keyword_ranked(query).limit(ai_agent.context_limit).map { |chunk| [chunk, chunk.keyword_rank] } unless embedding_model

    vector = AiAgents::LlmClient.new.embed([query], input_type: :query).first
    chunks.nearest_neighbors(:embedding, vector, distance: 'cosine').limit(ai_agent.context_limit).map { |chunk| [chunk, chunk.neighbor_distance] }
  end

  def relevance_check(embedding_model)
    return lambda(&:positive?) unless embedding_model

    max_distance = AiAgents::LlmClient.embedding_max_distance
    max_distance ? ->(distance) { distance <= max_distance } : ->(_distance) { true }
  end
end

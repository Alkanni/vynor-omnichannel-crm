# Finds the knowledge chunks an AI Agent sends to the model for a question, up to its Context Limit (see
# AiAgent::KnowledgeChunk.searchable for the chunks compared). With an embedding model the search is hybrid: the nearest
# chunks by embedding and the chunks sharing the most words with the question are combined with Reciprocal Rank Fusion,
# so vector search finds what means the same and keywords find exact names and numbers. Without one only the words count.
# Chunks that are not relevant enough are left out of their list: those sharing no word with the question, and those
# farther than AI_AGENT_EMBEDDING_MAX_DISTANCE when it is set. No chunk at all means the model answers without knowledge.
class AiAgents::KnowledgeRetriever
  # Fusion settings, chosen with evals/ai-agent: k evens out how much a top rank counts against a lower one, and keywords
  # count half as much as embeddings because they match on any shared word, however common.
  RRF_K = 20
  KEYWORD_WEIGHT = 0.5

  # rank starts at 1. score is the RRF score in hybrid mode and the ts_rank in keyword mode; in both, higher is closer.
  Hit = Data.define(:chunk, :rank, :score)
  Result = Data.define(:mode, :embedding_model, :hits)

  pattr_initialize [:ai_agent!, :query!]

  def perform
    embedding_model = AiAgents::LlmClient.embedding_model
    Result.new(mode: embedding_model ? 'hybrid' : 'keyword', embedding_model: embedding_model, hits: hits(embedding_model))
  end

  private

  def hits(embedding_model)
    chunks = ai_agent.knowledge_chunks.searchable(embedding_model)
    return [] if query.blank? || !chunks.exists?

    scored = embedding_model ? fused(chunks) : keyword_matches(chunks).map { |chunk| [chunk, chunk.keyword_rank] }
    scored.first(ai_agent.context_limit).map.with_index(1) { |(chunk, score), rank| Hit.new(chunk: chunk, rank: rank, score: score) }
  end

  # A chunk scores weight / (RRF_K + rank) for each list it is in, so one found by both searches ranks above one found by either.
  def fused(chunks)
    scores = Hash.new(0.0)
    [[nearest_chunks(chunks), 1.0], [keyword_matches(chunks), KEYWORD_WEIGHT]].each do |list, weight|
      list.each.with_index(1) { |chunk, rank| scores[chunk] += weight / (RRF_K + rank) }
    end
    scores.sort_by { |chunk, score| [-score, chunk.id] }
  end

  def nearest_chunks(chunks)
    vector = AiAgents::LlmClient.new.embed([query], input_type: :query).first
    nearest = chunks.nearest_neighbors(:embedding, vector, distance: 'cosine').limit(ai_agent.context_limit)
    max_distance = AiAgents::LlmClient.embedding_max_distance
    max_distance ? nearest.select { |chunk| chunk.neighbor_distance <= max_distance } : nearest
  end

  def keyword_matches(chunks)
    chunks.keyword_ranked(query).limit(ai_agent.context_limit).select { |chunk| chunk.keyword_rank.positive? }
  end
end

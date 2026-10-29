# Finds the knowledge chunks an AI Agent sends to the model for a question, up to its Context Limit: the nearest chunks
# by embedding when an embedding model is set, otherwise the chunks sharing the most words with the question.
# Only chunks embedded with the current embedding model are compared, since vectors of another model differ in
# meaning and often in size; they count again once the agent is trained with the current model.
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
    chunks = embedding_model ? ai_agent.knowledge_chunks.where(embedding_model: embedding_model) : ai_agent.knowledge_chunks
    return [] if query.blank? || !chunks.exists?

    chunks = if embedding_model
               chunks.nearest_neighbors(:embedding, AiAgents::LlmClient.new.embed([query], input_type: :query).first, distance: 'cosine')
             else
               chunks.keyword_ranked(query)
             end
    chunks.limit(ai_agent.context_limit).map.with_index(1) do |chunk, rank|
      Hit.new(chunk: chunk, rank: rank, score: embedding_model ? chunk.neighbor_distance : chunk.keyword_rank)
    end
  end
end

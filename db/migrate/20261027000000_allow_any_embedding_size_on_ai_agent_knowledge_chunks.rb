# Embedding models return vectors of their own size (e.g. 2048 for NVIDIA nemotron-3-embed-1b), so the column has no
# fixed dimensions and each chunk records the model it was embedded with.
class AllowAnyEmbeddingSizeOnAiAgentKnowledgeChunks < ActiveRecord::Migration[7.1]
  def up
    change_column :ai_agent_knowledge_chunks, :embedding, :vector
    add_column :ai_agent_knowledge_chunks, :embedding_model, :string
  end

  def down
    remove_column :ai_agent_knowledge_chunks, :embedding_model
    execute 'UPDATE ai_agent_knowledge_chunks SET embedding = NULL WHERE vector_dims(embedding) <> 1536'
    change_column :ai_agent_knowledge_chunks, :embedding, :vector, limit: 1536
  end
end

# Chunks are stored without vectors when no embedding model is configured and are then searched by keywords.
class AllowAiAgentKnowledgeChunksWithoutEmbedding < ActiveRecord::Migration[7.1]
  def change
    change_column_null :ai_agent_knowledge_chunks, :embedding, true
  end
end

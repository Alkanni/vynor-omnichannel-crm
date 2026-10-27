# Trains AI Agents again whose knowledge was embedded before chunks recorded their embedding model, so semantic
# search finds that knowledge again (now with query/passage prefixes) without waiting for someone to press Train.
class Migration::RetrainAiAgentsJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    legacy_chunks = AiAgent::KnowledgeChunk.where(embedding_model: nil).where.not(embedding: nil)
    AiAgent.where(id: legacy_chunks.select(:ai_agent_id)).find_each(&:schedule_training)
  end
end

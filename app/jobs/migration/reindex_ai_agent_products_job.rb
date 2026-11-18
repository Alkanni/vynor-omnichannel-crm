# Indexes the products of AI agents again after their chunk text left out blank fields and gained the price currency (#121).
# Their chunks are marked as made from an older version, so the indexer replaces them product by product and agents keep
# answering from the old chunks until then.
class Migration::ReindexAiAgentProductsJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    AiAgent::KnowledgeChunk.where(chunkable_type: AiAgent::Product.name)
                           .update_all(chunkable_updated_at: Time.zone.at(0)) # rubocop:disable Rails/SkipsModelValidations
    AiAgent.where(id: AiAgent::Product.select(:ai_agent_id)).find_each(&:schedule_training)
  end
end

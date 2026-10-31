# Chunks text, website, and file knowledge again after AiAgents::TextChunker learned headings and tables. Their chunks are
# marked as made from an older version, so the indexer replaces them source by source and agents keep answering from the
# old chunks until then. DOCX files are extracted again first, because their stored text lost its structure.
class Migration::RechunkAiAgentsJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    sources = AiAgent::KnowledgeSource.where.not(source_type: :qa)
    AiAgent::KnowledgeChunk.where(chunkable_type: 'AiAgent::KnowledgeSource', chunkable_id: sources.select(:id))
                           .update_all(chunkable_updated_at: Time.zone.at(0)) # rubocop:disable Rails/SkipsModelValidations
    sources.file.ready.joins(:file_blob).where('active_storage_blobs.filename ILIKE ?', '%.docx').find_each(&:resync!)
    AiAgent.where(id: sources.select(:ai_agent_id)).find_each(&:schedule_training)
  end
end

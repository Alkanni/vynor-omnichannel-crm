# Chunks text, website, and file knowledge again after AiAgents::TextChunker learned headings and tables. Their chunks are
# marked as made from an older version, so the indexer replaces them source by source and agents keep answering from the
# old chunks until then. DOCX files are extracted again first, because their stored text lost its structure. They stay ready
# meanwhile, since the indexer drops the chunks of a source that is not, and a file that cannot be read keeps its text.
class Migration::RechunkAiAgentsJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    sources = AiAgent::KnowledgeSource.where.not(source_type: :qa)
    sources.file.ready.joins(:file_blob).where('active_storage_blobs.filename ILIKE ?', '%.docx').find_each { |source| extract_again(source) }
    AiAgent::KnowledgeChunk.where(chunkable_type: 'AiAgent::KnowledgeSource', chunkable_id: sources.select(:id))
                           .update_all(chunkable_updated_at: Time.zone.at(0)) # rubocop:disable Rails/SkipsModelValidations
    AiAgent.where(id: sources.select(:ai_agent_id)).find_each(&:schedule_training)
  end

  private

  def extract_again(source)
    text = AiAgents::FileTextExtractor.new(source.file).perform
    source.store_extracted!(text) if text.present?
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: source.account).capture_exception
  end
end

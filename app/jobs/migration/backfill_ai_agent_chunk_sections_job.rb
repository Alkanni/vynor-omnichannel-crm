# Gives the knowledge chunks made before chunks kept their section (#134) their section without embedding them again, so
# their neighbors can be sent with them (see AiAgents::ContextExpansion). The text, website, and file sources whose chunks
# are of their current version are chunked again, and their chunks get the sections only when the new chunks are exactly
# the stored ones. Any other chunk keeps none, and so sends no neighbors, until the next indexing of its source.
class Migration::BackfillAiAgentChunkSectionsJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    unnumbered = AiAgent::KnowledgeChunk.where(chunkable_type: AiAgent::KnowledgeSource.name, section: nil).select(:chunkable_id)
    AiAgent::KnowledgeSource.where.not(source_type: :qa).where(id: unnumbered).find_each { |source| backfill(source) }
  end

  private

  # The indexer replaces all chunks of a source at once, so chunks of an older version leave none of the current one.
  def backfill(source)
    stored = AiAgent::KnowledgeChunk.where(chunkable: source, chunkable_updated_at: source.updated_at).order(:id).pluck(:id, :content)
    chunks = AiAgents::KnowledgeIndexer.chunks(source)
    return unless stored.map(&:last) == chunks.map(&:text)

    stored.zip(chunks) do |(id, _content), chunk|
      AiAgent::KnowledgeChunk.where(id: id).update_all(section: chunk.section) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end

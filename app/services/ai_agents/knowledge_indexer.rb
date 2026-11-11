# Brings an agent's knowledge chunks in line with its ready knowledge sources and products.
# Records are re-embedded only when their updated_at differs from the version stored on their chunks,
# and a source that is re-syncing or failed is left out until it is ready again. Chunks record the embedding
# model they were embedded with; without an embedding model they are stored without vectors for keyword search.
# A run that cannot embed records why on the agent for the Knowledge page (a request error is raised again so the job
# retries); the next complete run clears it. Each chunk keeps the section of its source it came from (see
# AiAgents::KnowledgeRetriever for how its neighbors in that section are sent with it).
class AiAgents::KnowledgeIndexer
  EMBEDDING_BATCH_SIZE = 100

  pattr_initialize [:ai_agent!]

  # The AiAgents::TextChunker::Chunk of each chunk of a record in document order, its text opening with the record's title.
  # A product or Q&A is one chunk without a section.
  def self.chunks(record)
    return [AiAgents::TextChunker::Chunk.new(section: nil, text: product_text(record))] if record.is_a?(AiAgent::Product)
    return [AiAgents::TextChunker::Chunk.new(section: nil, text: "Q: #{record.title}\nA: #{record.content}")] if record.qa?

    AiAgents::TextChunker.split(record.content).map { |chunk| chunk.with(text: "#{record.title}\n\n#{chunk.text}") }
  end

  def self.product_text(product)
    [
      "Product: #{product.name}",
      "Price: #{format('%.2f', product.price)}",
      "Weight: #{product.weight} grams",
      "Stock: #{product.stock}",
      ("Description: #{product.description}" if product.description.present?)
    ].compact.join("\n")
  end
  private_class_method :product_text

  def perform
    indexable = indexable_versions
    remove_stale_chunks(indexable)
    @embedding_model = AiAgents::LlmClient.embedding_model
    return record_failure(I18n.t('ai_agents.llm.errors.not_configured')) if @embedding_model && AiAgents::LlmClient.embedding_api_key.blank?

    index_changed_records(indexable)
    ai_agent.update_columns(trained_at: Time.current, training_error: nil, training_failed_at: nil) # rubocop:disable Rails/SkipsModelValidations
  rescue AiAgents::LlmError => e
    record_failure(e.message)
    raise
  end

  private

  def index_changed_records(indexable)
    indexed = indexed_chunks.group(:chunkable_type, :chunkable_id).maximum(:chunkable_updated_at)
    indexable.each do |klass, versions|
      changed_ids = versions.reject { |id, version| indexed[[klass.name, id]] == version }.keys
      klass.where(id: changed_ids).find_each { |record| index(record) }
    end
  end

  def record_failure(message)
    ai_agent.update_columns(training_error: message, training_failed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def indexable_versions
    {
      AiAgent::KnowledgeSource => ai_agent.knowledge_sources.ready.where.not(content: [nil, '']).pluck(:id, :updated_at).to_h,
      AiAgent::Product => ai_agent.products.pluck(:id, :updated_at).to_h
    }
  end

  def remove_stale_chunks(indexable)
    indexable.each do |klass, versions|
      ai_agent.knowledge_chunks.where(chunkable_type: klass.name).where.not(chunkable_id: versions.keys).delete_all
    end
  end

  # Chunks stored for keyword search or embedded with another model are embedded again with the current one.
  def indexed_chunks
    @embedding_model ? ai_agent.knowledge_chunks.where(embedding_model: @embedding_model) : ai_agent.knowledge_chunks
  end

  def index(record)
    version = record.updated_at
    chunks = self.class.chunks(record)
    texts = chunks.map(&:text)
    embeddings = @embedding_model ? texts.each_slice(EMBEDDING_BATCH_SIZE).flat_map { |batch| client.embed(batch, input_type: :passage) } : []

    record.with_lock do
      # The record changed while it was being embedded; the job queued by that change indexes it.
      next unless record.updated_at == version

      ai_agent.knowledge_chunks.where(chunkable: record).delete_all
      chunks.zip(embeddings).each do |chunk, embedding|
        AiAgent::KnowledgeChunk.create!(account_id: ai_agent.account_id, ai_agent: ai_agent, chunkable: record, chunkable_updated_at: version,
                                        content: chunk.text, section: chunk.section, embedding: embedding, embedding_model: @embedding_model)
      end
    end
  end

  def client
    @client ||= AiAgents::LlmClient.new
  end
end

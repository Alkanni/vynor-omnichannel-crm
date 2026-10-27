# Brings an agent's knowledge chunks in line with its ready knowledge sources and products.
# Records are re-embedded only when their updated_at differs from the version stored on their chunks,
# and a source that is re-syncing or failed is left out until it is ready again. Chunks record the embedding
# model they were embedded with; without an embedding model they are stored without vectors for keyword search.
class AiAgents::KnowledgeIndexer
  EMBEDDING_BATCH_SIZE = 100

  pattr_initialize [:ai_agent!]

  def perform
    indexable = indexable_versions
    remove_stale_chunks(indexable)
    @embedding_model = AiAgents::LlmClient.embedding_model
    return if @embedding_model && AiAgents::LlmClient.embedding_api_key.blank?

    indexed = indexed_chunks.group(:chunkable_type, :chunkable_id).maximum(:chunkable_updated_at)
    indexable.each do |klass, versions|
      changed_ids = versions.reject { |id, version| indexed[[klass.name, id]] == version }.keys
      klass.where(id: changed_ids).find_each { |record| index(record) }
    end
    ai_agent.update_column(:trained_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

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
    texts = chunk_texts(record)
    embeddings = @embedding_model ? texts.each_slice(EMBEDDING_BATCH_SIZE).flat_map { |batch| client.embed(batch, input_type: :passage) } : []

    record.with_lock do
      # The record changed while it was being embedded; the job queued by that change indexes it.
      next unless record.updated_at == version

      ai_agent.knowledge_chunks.where(chunkable: record).delete_all
      texts.zip(embeddings).each do |content, embedding|
        AiAgent::KnowledgeChunk.create!(account_id: ai_agent.account_id, ai_agent: ai_agent, chunkable: record, chunkable_updated_at: version,
                                        content: content, embedding: embedding, embedding_model: @embedding_model)
      end
    end
  end

  def chunk_texts(record)
    return [product_text(record)] if record.is_a?(AiAgent::Product)
    return ["Q: #{record.title}\nA: #{record.content}"] if record.qa?

    AiAgents::TextChunker.split(record.content).map { |chunk| "#{record.title}\n\n#{chunk}" }
  end

  def product_text(product)
    [
      "Product: #{product.name}",
      "Price: #{format('%.2f', product.price)}",
      "Weight: #{product.weight} grams",
      "Stock: #{product.stock}",
      ("Description: #{product.description}" if product.description.present?)
    ].compact.join("\n")
  end

  def client
    @client ||= AiAgents::LlmClient.new
  end
end

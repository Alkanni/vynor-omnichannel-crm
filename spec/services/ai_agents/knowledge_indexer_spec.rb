require 'rails_helper'

RSpec.describe AiAgents::KnowledgeIndexer do
  let(:ai_agent) { create(:ai_agent) }
  let(:client) { instance_double(AiAgents::LlmClient) }
  let(:indexer) { described_class.new(ai_agent: ai_agent) }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    create(:installation_config, name: 'AI_AGENT_EMBEDDING_MODEL', value: 'text-embedding-3-small')
    allow(AiAgents::LlmClient).to receive(:new).and_return(client)
    allow(client).to receive(:embed) { |texts, **| Array.new(texts.size) { Array.new(1536, 0.1) } }
  end

  it 'indexes ready knowledge sources and products and records the training time' do
    text = create(:ai_agent_knowledge_source, ai_agent: ai_agent)
    qa = create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
    create(:ai_agent_product, ai_agent: ai_agent, name: 'Paket Detailing', price: 750_000, weight: nil, stock: 3, description: nil)
    create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, external_url: 'https://example.com', content: nil)

    indexer.perform

    expect(ai_agent.knowledge_chunks.pluck(:content)).to contain_exactly(
      "#{text.title}\n\n#{text.content}",
      "Q: #{qa.title}\nA: #{qa.content}",
      "Product: Paket Detailing\nPrice: IDR 750000.00\nStock: 3"
    )
    expect(ai_agent.knowledge_chunks.distinct.pluck(:embedding_model)).to eq(['text-embedding-3-small'])
    expect(client).to have_received(:embed).with(["#{text.title}\n\n#{text.content}"], input_type: :passage)
    expect(ai_agent.reload.trained_at).to be_present
  end

  it 'writes the recorded numbers of a product, 0 too, with the price in the installation currency, and leaves out blank ones' do
    create(:installation_config, name: 'AI_AGENT_PRODUCT_CURRENCY', value: 'USD')
    create(:ai_agent_product, ai_agent: ai_agent, name: 'Roti Sobek', price: 0, weight: 400, stock: 0, description: 'Gratis untuk pembeli pertama')
    create(:ai_agent_product, ai_agent: ai_agent, name: 'Konsultasi', price: nil, weight: nil, stock: nil, description: nil)

    indexer.perform

    expect(ai_agent.knowledge_chunks.pluck(:content)).to contain_exactly(
      "Product: Roti Sobek\nPrice: USD 0.00\nWeight: 400 grams\nStock: 0\nDescription: Gratis untuk pembeli pertama",
      'Product: Konsultasi'
    )
  end

  describe 'promotions' do
    # 10:00 on 25 November 2026 in Asia/Jakarta, the default timezone of an AI agent.
    before { travel_to(Time.utc(2026, 11, 25, 3, 0)) }

    def promotion_chunks
      ai_agent.knowledge_chunks.where(chunkable_type: AiAgent::Promotion.name).pluck(:content)
    end

    it 'writes the period, the products, and the details of each promotion that is not archived, as one chunk without a section' do
      products = [create(:ai_agent_product, ai_agent: ai_agent, name: 'Stabill'), create(:ai_agent_product, ai_agent: ai_agent, name: 'Oli Mesin')]
      create(:ai_agent_promotion, ai_agent: ai_agent, title: 'Diskon November', description: 'Stabill Rp80.000', products: products,
                                  starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 30))
      create(:ai_agent_promotion, ai_agent: ai_agent, title: 'Gratis cuci', description: 'Gratis cuci untuk servis besar')
      create(:ai_agent_promotion, ai_agent: ai_agent, title: 'Akhir tahun', description: 'Diskon 10%', starts_on: Date.new(2026, 12, 20))
      create(:ai_agent_promotion, ai_agent: ai_agent, title: 'Oktober', description: 'Sudah lewat', ends_on: Date.new(2026, 11, 24))

      indexer.perform

      expect(promotion_chunks).to contain_exactly(
        "Promotion: Diskon November\nValid: from 1 November 2026 until 30 November 2026\nApplies to: Stabill, Oli Mesin\nDetails: Stabill Rp80.000",
        "Promotion: Gratis cuci\nValid: with no end date\nDetails: Gratis cuci untuk servis besar",
        "Promotion: Akhir tahun\nValid: from 20 December 2026 with no end date\nDetails: Diskon 10%"
      )
      expect(ai_agent.knowledge_chunks.where(chunkable_type: AiAgent::Promotion.name).pluck(:section)).to all(be_nil)
    end

    it 'rewrites a promotion when a product it applies to is renamed or deleted, and removes it once archived' do
      product = create(:ai_agent_product, ai_agent: ai_agent, name: 'Stabill')
      create(:ai_agent_promotion, ai_agent: ai_agent, title: 'Diskon', description: 'Rp80.000', ends_on: Date.new(2026, 11, 25), products: [product])
      indexer.perform

      travel 1.minute
      product.update!(name: 'Stabill Plus')
      indexer.perform
      expect(promotion_chunks).to eq(["Promotion: Diskon\nValid: until 25 November 2026\nApplies to: Stabill Plus\nDetails: Rp80.000"])

      travel 1.minute
      product.destroy!
      indexer.perform
      expect(promotion_chunks).to eq(["Promotion: Diskon\nValid: until 25 November 2026\nDetails: Rp80.000"])

      # 00:00 on 26 November in Asia/Jakarta.
      travel_to(Time.utc(2026, 11, 25, 17, 0))
      indexer.perform
      expect(promotion_chunks).to be_empty
    end
  end

  it 'logs each batch it embedded without the texts, with the request log on' do
    create(:installation_config, name: 'AI_AGENT_REQUEST_LOG_ENABLED', value: 'true')
    allow(AiAgents::LlmClient).to receive(:new).and_call_original
    stub_request(:post, 'https://api.openai.com/v1/embeddings').to_return do |request|
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { data: JSON.parse(request.body)['input'].map { { embedding: Array.new(1536, 0.1) } } }.to_json }
    end
    stub_const('AiAgents::KnowledgeIndexer::EMBEDDING_BATCH_SIZE', 2)
    content = "Pembuka.\n\n# Syarat\n\n#{(['kata'] * 400).join(' ')}\n\n# Biaya\n\nRp10.000"
    text = create(:ai_agent_knowledge_source, ai_agent: ai_agent, content: content)

    indexer.perform

    log = AiAgent::RequestLog.sole
    expect(log).to have_attributes(source: 'indexing', status: 'ok', conversation_id: nil, input: { 'embedding_model' => 'text-embedding-3-small' })
    expect(log.steps.map { |step| step.slice('step', 'input', 'output', 'model') }).to eq(
      [[2, 2], [2, 2]].map do |chunks, vectors|
        { 'step' => 'embedding', 'input' => { 'chunkable_type' => 'AiAgent::KnowledgeSource', 'chunkable_id' => text.id, 'chunks' => chunks },
          'output' => { 'vectors' => vectors, 'dimensions' => 1536 }, 'model' => 'text-embedding-3-small' }
      end
    )
    expect(log.attributes.to_json).not_to include('Pembuka', 'Rp10.000')
  end

  it 'stores the section of each chunk of a text source, and none for a Q&A entry or a product' do
    content = "Pembuka.\n\n# Syarat\n\n#{(['kata'] * 400).join(' ')}\n\n# Biaya\n\nRp10.000"
    text = create(:ai_agent_knowledge_source, ai_agent: ai_agent, content: content)
    create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
    create(:ai_agent_product, ai_agent: ai_agent)

    indexer.perform

    expect(ai_agent.knowledge_chunks.where(chunkable: text).order(:id).pluck(:section)).to eq([0, 1, 1, 2])
    expect(ai_agent.knowledge_chunks.where.not(chunkable: text).pluck(:section)).to eq([nil, nil])
  end

  it 'embeds chunks again when the embedding model changes, whatever its vector size' do
    create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
    indexer.perform

    InstallationConfig.find_by(name: 'AI_AGENT_EMBEDDING_MODEL').update!(value: 'nvidia/nvidia/nemotron-3-embed-1b')
    allow(client).to receive(:embed) { |texts, **| Array.new(texts.size) { Array.new(2048, 0.2) } }
    indexer.perform

    chunk = ai_agent.knowledge_chunks.sole
    expect(chunk.embedding_model).to eq('nvidia/nvidia/nemotron-3-embed-1b')
    expect(chunk.embedding.size).to eq(2048)
  end

  it 'embeds only records that changed since the last run and drops deleted ones' do
    text = create(:ai_agent_knowledge_source, ai_agent: ai_agent)
    qa = create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
    indexer.perform

    text.update!(content: 'Buka setiap hari pukul 08.00 - 17.00.')
    qa.destroy!
    indexer.perform

    expect(client).to have_received(:embed).exactly(3).times
    expect(ai_agent.knowledge_chunks.pluck(:content)).to eq(["#{text.title}\n\nBuka setiap hari pukul 08.00 - 17.00."])
  end

  it 'leaves out sources that are re-syncing' do
    source = create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, external_url: 'https://example.com',
                                                content: 'Old page', status: :ready)
    indexer.perform
    source.update!(status: :pending)

    indexer.perform

    expect(ai_agent.knowledge_chunks).to be_empty
  end

  it 'only removes stale chunks when the API key is not configured' do
    qa = create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
    indexer.perform
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy!
    ai_agent.update_column(:trained_at, nil) # rubocop:disable Rails/SkipsModelValidations
    qa.destroy!
    create(:ai_agent_knowledge_source, ai_agent: ai_agent)

    indexer.perform

    expect(ai_agent.knowledge_chunks).to be_empty
    expect(client).to have_received(:embed).once
    expect(ai_agent.reload).to have_attributes(trained_at: nil, training_error: I18n.t('ai_agents.llm.errors.not_configured'),
                                               training_failed_at: be_present)
  end

  it 'records why the embedding request failed and raises it again so the job retries' do
    create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
    allow(client).to receive(:embed).and_raise(AiAgents::LlmError, 'The AI model request failed (TimeoutError)')

    expect { indexer.perform }.to raise_error(AiAgents::LlmError)
    expect(ai_agent.reload).to have_attributes(trained_at: nil, training_error: 'The AI model request failed (TimeoutError)',
                                               training_failed_at: be_present)
  end

  it 'clears the recorded error once a run completes' do
    ai_agent.update!(training_error: 'The AI model request failed (TimeoutError)', training_failed_at: 1.hour.ago)
    create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)

    indexer.perform

    expect(ai_agent.reload).to have_attributes(trained_at: be_present, training_error: nil, training_failed_at: nil)
  end

  context 'without an embedding model' do
    before { InstallationConfig.find_by(name: 'AI_AGENT_EMBEDDING_MODEL').update!(value: '') }

    it 'stores the chunks without embeddings for keyword search, even without an API key' do
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy!
      qa = create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)

      indexer.perform

      expect(ai_agent.knowledge_chunks.pluck(:content, :embedding)).to eq([["Q: #{qa.title}\nA: #{qa.content}", nil]])
      expect(client).not_to have_received(:embed)
      expect(ai_agent.reload.trained_at).to be_present
    end

    it 'embeds those chunks once an embedding model is set' do
      create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
      indexer.perform

      InstallationConfig.find_by(name: 'AI_AGENT_EMBEDDING_MODEL').update!(value: 'text-embedding-3-small')
      indexer.perform

      expect(client).to have_received(:embed).once
      expect(ai_agent.knowledge_chunks.sole.embedding).to eq(Array.new(1536, 0.1))
    end
  end
end

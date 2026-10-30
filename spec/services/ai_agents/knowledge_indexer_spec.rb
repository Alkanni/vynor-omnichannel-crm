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
    create(:ai_agent_product, ai_agent: ai_agent, name: 'Paket Detailing', price: 750_000, weight: 0, stock: 3, description: nil)
    create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, external_url: 'https://example.com', content: nil)

    indexer.perform

    expect(ai_agent.knowledge_chunks.pluck(:content)).to contain_exactly(
      "#{text.title}\n\n#{text.content}",
      "Q: #{qa.title}\nA: #{qa.content}",
      "Product: Paket Detailing\nPrice: 750000.00\nWeight: 0 grams\nStock: 3"
    )
    expect(ai_agent.knowledge_chunks.distinct.pluck(:embedding_model)).to eq(['text-embedding-3-small'])
    expect(client).to have_received(:embed).with(["#{text.title}\n\n#{text.content}"], input_type: :passage)
    expect(ai_agent.reload.trained_at).to be_present
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

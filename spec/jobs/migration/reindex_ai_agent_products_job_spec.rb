require 'rails_helper'

RSpec.describe Migration::ReindexAiAgentProductsJob do
  let(:ai_agent) { create(:ai_agent) }
  let(:text_agent) { create(:ai_agent) }
  let(:product) { create(:ai_agent_product, ai_agent: ai_agent, name: 'Paket Detailing', price: 750_000, weight: nil, stock: 3, description: nil) }
  let(:text) { create(:ai_agent_knowledge_source, ai_agent: text_agent) }

  before do
    [product, text].each do |record|
      record.ai_agent.knowledge_chunks.create!(account: record.account, chunkable: record, chunkable_updated_at: record.updated_at,
                                               content: 'Teks lama', embedding_model: nil)
    end
    allow(Redis::Alfred).to receive(:set).and_return(true)
  end

  it 'schedules training only for agents with products, keeping their chunks until it runs' do
    expect { described_class.perform_now }
      .to have_enqueued_job(AiAgents::IndexKnowledgeJob).with(ai_agent)
      .and have_enqueued_job(AiAgents::IndexKnowledgeJob).exactly(:once)

    expect(ai_agent.knowledge_chunks.sole.content).to eq('Teks lama')
    expect(text_agent.knowledge_chunks.sole.chunkable_updated_at).to eq(text.updated_at)
  end

  it 'makes the indexer write the product chunk again in the new format' do
    described_class.perform_now
    AiAgents::KnowledgeIndexer.new(ai_agent: ai_agent).perform

    expect(ai_agent.knowledge_chunks.sole.content).to eq("Product: Paket Detailing\nPrice: IDR 750000.00\nStock: 3")
  end
end

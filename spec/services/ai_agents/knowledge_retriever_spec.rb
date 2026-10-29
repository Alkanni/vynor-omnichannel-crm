require 'rails_helper'

RSpec.describe AiAgents::KnowledgeRetriever do
  let(:ai_agent) { create(:ai_agent, context_limit: 2) }
  let(:source) { create(:ai_agent_knowledge_source, ai_agent: ai_agent) }
  let(:query_vector) { Array.new(1536) { |index| index.zero? ? 1.0 : 0.0 } }
  let(:embedding_requests) { [] }

  def create_chunk(content, embedding: nil, embedding_model: nil)
    ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: source, chunkable_updated_at: source.updated_at,
                                      content: content, embedding: embedding, embedding_model: embedding_model)
  end

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    stub_request(:post, 'https://api.openai.com/v1/embeddings').to_return do |request|
      embedding_requests << JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { data: [{ embedding: query_vector }] }.to_json }
    end
  end

  context 'with an embedding model' do
    before { create(:installation_config, name: 'AI_AGENT_EMBEDDING_MODEL', value: 'text-embedding-3-small') }

    it 'returns the nearest chunks of the current embedding model up to the context limit, with their cosine distance' do
      closest = create_chunk('Jam buka', embedding: query_vector, embedding_model: 'text-embedding-3-small')
      create_chunk('Alamat', embedding: Array.new(1536) { |index| index == 2 ? 1.0 : 0.0 }, embedding_model: 'text-embedding-3-small')
      close = create_chunk('Harga', embedding: Array.new(1536) { |index| index < 2 ? 1.0 : 0.0 }, embedding_model: 'text-embedding-3-small')
      create_chunk('Model lama', embedding: query_vector, embedding_model: 'old-model')

      result = described_class.new(ai_agent: ai_agent, query: 'Jam buka?').perform

      expect(result).to have_attributes(mode: 'vector', embedding_model: 'text-embedding-3-small')
      expect(result.hits.map { |hit| [hit.chunk, hit.rank] }).to eq([[closest, 1], [close, 2]])
      expect(result.hits.map(&:score)).to match([be_within(1e-6).of(0), be_within(1e-6).of(1 - Math.sqrt(0.5))])
      expect(embedding_requests.sole['input']).to eq(['query: Jam buka?'])
    end

    it 'does not embed the query when no chunk uses the current embedding model' do
      create_chunk('Model lama', embedding: query_vector, embedding_model: 'old-model')

      expect(described_class.new(ai_agent: ai_agent, query: 'Jam buka?').perform.hits).to be_empty
      expect(embedding_requests).to be_empty
    end
  end

  context 'without an embedding model' do
    it 'ranks chunks by the words they share with the query, with their ts_rank' do
      partial = create_chunk('Harga detailing mobil')
      create_chunk('Jam buka setiap hari')
      full = create_chunk('Harga detailing interior Rp750.000')
      create_chunk('Harga cuci')

      result = described_class.new(ai_agent: ai_agent, query: 'harga detailing interior').perform

      expect(result).to have_attributes(mode: 'keyword', embedding_model: nil)
      expect(result.hits.map { |hit| [hit.chunk, hit.rank] }).to eq([[full, 1], [partial, 2]])
      expect(result.hits.map(&:score)).to all(be > 0)
      expect(result.hits.first.score).to be > result.hits.last.score
      expect(embedding_requests).to be_empty
    end
  end

  it 'returns no chunks for a blank query' do
    create_chunk('Jam buka')

    expect(described_class.new(ai_agent: ai_agent, query: ' ').perform.hits).to be_empty
  end
end

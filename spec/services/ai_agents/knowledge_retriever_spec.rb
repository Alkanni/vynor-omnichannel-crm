require 'rails_helper'

RSpec.describe AiAgents::KnowledgeRetriever do
  let(:ai_agent) { create(:ai_agent, context_limit: 2) }
  let(:source) { create(:ai_agent_knowledge_source, ai_agent: ai_agent) }
  let(:query_vector) { Array.new(1536) { |index| index.zero? ? 1.0 : 0.0 } }
  let(:close_vector) { Array.new(1536) { |index| index < 2 ? 1.0 : 0.0 } }
  let(:far_vector) { Array.new(1536) { |index| index == 2 ? 1.0 : 0.0 } }
  let(:embedding_requests) { [] }

  def create_chunk(content, embedding: nil, embedding_model: nil, section: nil)
    ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: source, chunkable_updated_at: source.updated_at,
                                      content: content, embedding: embedding, embedding_model: embedding_model, section: section)
  end

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    stub_request(:post, 'https://api.openai.com/v1/embeddings').to_return do |request|
      body = JSON.parse(request.body)
      embedding_requests << body
      { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { data: body['input'].map { { embedding: query_vector } } }.to_json }
    end
  end

  context 'with an embedding model' do
    before { create(:installation_config, name: 'AI_AGENT_EMBEDDING_MODEL', value: 'text-embedding-3-small') }

    it 'fuses the nearest chunks of the current embedding model and the keyword matches, one hit per chunk up to the context limit' do
      ai_agent.update!(context_limit: 3)
      create_chunk('Jam buka lama', embedding: query_vector, embedding_model: 'old-model')
      farthest = create_chunk('Jam buka setiap hari', embedding: far_vector, embedding_model: 'text-embedding-3-small')
      closest = create_chunk('Alamat toko', embedding: query_vector, embedding_model: 'text-embedding-3-small')
      both = create_chunk('Jam operasional', embedding: close_vector, embedding_model: 'text-embedding-3-small')
      create_chunk('Harga cuci', embedding: Array.new(1536) { |index| index < 3 ? 1.0 : 0.0 }, embedding_model: 'text-embedding-3-small')

      result = described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'Jam buka?' }]).perform

      expect(result).to have_attributes(mode: 'hybrid', embedding_model: 'text-embedding-3-small')
      # The lists hold more chunks than the context limit, so the farthest chunk counts its fourth place by embedding too.
      expect(result.hits.map { |hit| [hit.chunk, hit.rank] }).to eq([[both, 1], [farthest, 2], [closest, 3]])
      expect(result.hits.map(&:score)).to match([be_within(1e-9).of(1.5 / 22), be_within(1e-9).of((1 / 24.0) + (0.5 / 21)),
                                                 be_within(1e-9).of(1 / 21.0)])
      expect(embedding_requests.sole['input']).to eq(['query: Jam buka?'])
    end

    it 'takes as many chunks per list as the context limit when it is above the candidates' do
      stub_const("#{described_class}::CANDIDATES", 1)
      closest = create_chunk('Alamat toko', embedding: query_vector, embedding_model: 'text-embedding-3-small')
      next_closest = create_chunk('Harga cuci', embedding: close_vector, embedding_model: 'text-embedding-3-small')
      create_chunk('Jam buka', embedding: far_vector, embedding_model: 'text-embedding-3-small')

      result = described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'Jam buka?' }]).perform

      expect(result.hits.map(&:chunk)).to eq([closest, next_closest])
    end

    it 'leaves out chunks farther than the max embedding distance unless they share a word with the query' do
      create(:installation_config, name: 'AI_AGENT_EMBEDDING_MAX_DISTANCE', value: '0.5')
      keyword_match = create_chunk('Jam buka', embedding: far_vector, embedding_model: 'text-embedding-3-small')
      closest = create_chunk('Alamat toko', embedding: query_vector, embedding_model: 'text-embedding-3-small')
      create_chunk('Harga cuci', embedding: far_vector, embedding_model: 'text-embedding-3-small')

      result = described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'Jam buka?' }]).perform

      expect(result.hits.map { |hit| [hit.chunk, hit.rank] }).to eq([[closest, 1], [keyword_match, 2]])
    end

    it 'returns no chunks when none is within the max embedding distance or shares a word with the query' do
      create(:installation_config, name: 'AI_AGENT_EMBEDDING_MAX_DISTANCE', value: '0.5')
      create_chunk('Alamat toko', embedding: far_vector, embedding_model: 'text-embedding-3-small')

      expect(described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'Jam buka?' }]).perform.hits).to be_empty
    end

    it 'embeds both queries of a follow-up in one request and scores a chunk for each list it is in' do
      chunk = create_chunk('Alamat toko', embedding: query_vector, embedding_model: 'text-embedding-3-small')
      messages = [{ role: :user, content: 'Ada Roti Keju?' }, { role: :assistant, content: 'Ada.' }, { role: :user, content: 'Kalau beli 4?' }]

      result = described_class.new(ai_agent: ai_agent, messages: messages).perform

      expect(embedding_requests.sole['input']).to eq(['query: Kalau beli 4?', "query: Ada Roti Keju?\nKalau beli 4?"])
      expect(result.hits.sole).to have_attributes(chunk: chunk, rank: 1, score: be_within(1e-9).of(5 / 21.0))
    end

    it 'does not embed the query when no chunk uses the current embedding model' do
      create_chunk('Model lama', embedding: query_vector, embedding_model: 'old-model')

      expect(described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'Jam buka?' }]).perform.hits).to be_empty
      expect(embedding_requests).to be_empty
    end
  end

  context 'without an embedding model' do
    it 'ranks chunks by the words they share with the query' do
      partial = create_chunk('Harga detailing mobil')
      create_chunk('Jam buka setiap hari')
      full = create_chunk('Harga detailing interior Rp750.000')
      create_chunk('Harga cuci')

      result = described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'harga detailing interior' }]).perform

      expect(result).to have_attributes(mode: 'keyword', embedding_model: nil)
      expect(result.hits.map { |hit| [hit.chunk, hit.rank] }).to eq([[full, 1], [partial, 2]])
      expect(result.hits.map(&:score)).to all(be > 0)
      expect(result.hits.first.score).to be > result.hits.last.score
      expect(embedding_requests).to be_empty
    end

    it 'matches Indonesian word forms' do
      match = create_chunk('Pemesanan dibuat 3 hari sebelumnya')
      create_chunk('Jam buka setiap hari')

      expect(described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'pesan' }]).perform.hits.map(&:chunk)).to eq([match])
    end

    it 'leaves out chunks that share no word with the query' do
      match = create_chunk('Harga detailing mobil')
      create_chunk('Jam buka setiap hari')

      expect(described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'harga cuci' }]).perform.hits.map(&:chunk)).to eq([match])
    end
  end

  describe 'context expansion' do
    let(:messages) { [{ role: :user, content: 'harga detailing interior' }] }
    let!(:chunks) do
      ['Langkah 1: daftar.', 'Harga detailing interior Rp750.000', 'Langkah 3: bayar.', 'Harga detailing mobil'].map do |content|
        create_chunk(content, section: 0)
      end
    end

    before { ai_agent.update!(context_limit: 4) }

    it 'sends the matches alone, in the order and with the ranks and scores of the search, at radius 0' do
      ai_agent.update!(context_expansion_radius: 0)

      hits = described_class.new(ai_agent: ai_agent, messages: messages).perform.hits

      expect(hits.map { |hit| [hit.chunk, hit.rank, hit.neighbor_of] }).to eq([[chunks[1], 1, nil], [chunks[3], 2, nil]])
      expect(hits.first.score).to be > hits.last.score
    end

    it 'adds the neighbors of the matches in document order, within the context limit, at a radius above 0' do
      ai_agent.update!(context_expansion_radius: 0)
      scores = described_class.new(ai_agent: ai_agent, messages: messages).perform.hits.to_h { |hit| [hit.chunk, hit.score] }
      ai_agent.update!(context_expansion_radius: 1)

      hits = described_class.new(ai_agent: ai_agent, messages: messages).perform.hits

      expect(hits.map { |hit| [hit.chunk, hit.rank, hit.neighbor_of] }).to eq(
        [[chunks[0], 1, 2], [chunks[1], 2, nil], [chunks[2], 3, 2], [chunks[3], 4, nil]]
      )
      expect(hits.map(&:score)).to eq([nil, scores[chunks[1]], nil, scores[chunks[3]]])
    end
  end

  describe 'queries' do
    let(:reply) { { role: :assistant, content: 'Ada, Rp27.000.' } }

    it 'searches a first message on its own' do
      result = described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: 'Jam buka?' }]).perform

      expect(result.queries).to eq(['Jam buka?'])
    end

    it 'searches a burst of messages as one question, without a welcome message' do
      messages = [reply, { role: :user, content: 'Jam buka?' }, { role: :user, content: 'Hari Minggu juga?' }]

      expect(described_class.new(ai_agent: ai_agent, messages: messages).perform.queries).to eq(["Jam buka?\nHari Minggu juga?"])
    end

    it 'adds a query with the earlier customer turns after a reply, without the reply' do
      messages = [{ role: :user, content: 'Ada Roti Keju?' }, reply, { role: :user, content: 'Kalau beli 4?' }]

      expect(described_class.new(ai_agent: ai_agent, messages: messages).perform.queries).to eq(['Kalau beli 4?', "Ada Roti Keju?\nKalau beli 4?"])
    end

    it 'keeps two earlier turns' do
      messages = %w[Satu Dua Tiga Empat].flat_map { |content| [{ role: :user, content: content }, reply] }.tap(&:pop)

      expect(described_class.new(ai_agent: ai_agent, messages: messages).perform.queries).to eq(%W[Empat Dua\nTiga\nEmpat])
    end

    it 'limits the earlier turns and each query' do
      messages = [{ role: :user, content: 'a' * 5_000 }, reply, { role: :user, content: 'Kalau beli 4?' }]
      expect(described_class.new(ai_agent: ai_agent, messages: messages).perform.queries.last).to eq("#{'a' * 1_000}\nKalau beli 4?")

      messages = [{ role: :user, content: 'Ada Roti Keju?' }, reply, { role: :user, content: 'b' * 5_000 }]
      queries = described_class.new(ai_agent: ai_agent, messages: messages).perform.queries
      expect(queries.map(&:length)).to eq([4_000, 4_000])
    end

    it 'finds what a follow-up refers to through the earlier turn' do
      subject_chunk = create_chunk('Roti Keju lembut')
      follow_up = create_chunk('Harga total termasuk kemasan')
      messages = [{ role: :user, content: 'Ada Roti Keju?' }, reply, { role: :user, content: 'Harga total?' }]

      expect(described_class.new(ai_agent: ai_agent, messages: messages).perform.hits.map(&:chunk)).to contain_exactly(subject_chunk, follow_up)
    end

    it 'keeps a chunk matching a new topic above one matching only the earlier turn' do
      create_chunk('Roti Keju lembut')
      new_topic = create_chunk('Tempat parkir luas')
      messages = [{ role: :user, content: 'Ada Roti Keju?' }, reply, { role: :user, content: 'Tempat parkir?' }]

      expect(described_class.new(ai_agent: ai_agent, messages: messages).perform.hits.first.chunk).to eq(new_topic)
    end
  end

  it 'returns no chunks for a blank query' do
    create_chunk('Jam buka')

    expect(described_class.new(ai_agent: ai_agent, messages: [{ role: :user, content: ' ' }]).perform.hits).to be_empty
  end
end

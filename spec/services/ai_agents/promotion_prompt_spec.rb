require 'rails_helper'

RSpec.describe AiAgents::PromotionPrompt do
  let(:ai_agent) { create(:ai_agent) }
  let(:oil) { create(:ai_agent_product, ai_agent: ai_agent, name: 'Oli Mesin') }
  let(:brake) { create(:ai_agent_product, ai_agent: ai_agent, name: 'Kampas Rem') }
  let(:hours) { create_chunk(create(:ai_agent_knowledge_source, ai_agent: ai_agent), 'Jam buka: 08.00 - 17.00') }
  let(:oil_chunk) { create_chunk(oil, 'Product: Oli Mesin') }
  let(:brake_chunk) { create_chunk(brake, 'Product: Kampas Rem') }
  let(:prompt) { described_class.new(ai_agent: ai_agent, mentioned_ids: []) }

  def create_chunk(chunkable, content)
    ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: chunkable, chunkable_updated_at: chunkable.updated_at, content: content)
  end

  # The chunk of a new promotion of the agent.
  def promotion_chunk(content, **attributes)
    create_chunk(create(:ai_agent_promotion, ai_agent: ai_agent, **attributes), content)
  end

  # Hits in the order of their scores, as the search ranks them.
  def retrieval(*chunks)
    hits = chunks.map.with_index(1) { |chunk, rank| AiAgents::KnowledgeRetriever::Hit.new(chunk: chunk, rank: rank, score: 1.0 / rank) }
    AiAgents::KnowledgeRetriever::Result.new(mode: 'keyword', embedding_model: nil, queries: ['oli'], hits: hits)
  end

  # 10:00 on 25 November 2026 in Asia/Jakarta, the default timezone of an AI agent.
  before { travel_to(Time.utc(2026, 11, 25, 3, 0)) }

  describe '#arrange' do
    it 'offers the promotion of the product the best match is after the knowledge, without the promotion the knowledge had' do
      offer = promotion_chunk('Promotion: Diskon oli', products: [oil])
      passive = promotion_chunk('Promotion: Gratis cek rem')

      result = prompt.arrange(retrieval(oil_chunk, hours, passive))

      expect(result.hits.map { |hit| [hit.chunk, hit.rank] }).to eq([[oil_chunk, 1], [hours, 2], [offer, 3]])
      expect(result.offer).to have_attributes(chunk: offer, rank: 3, score: nil)
      expect(result.knowledge_hits.map(&:chunk)).to eq([oil_chunk, hours])
    end

    it 'offers a promotion whose own chunk is in the hits, moved after the knowledge' do
      offer = promotion_chunk('Promotion: Gratis cek rem')

      result = prompt.arrange(retrieval(offer, hours))

      expect(result.hits.map { |hit| [hit.chunk, hit.rank] }).to eq([[hours, 1], [offer, 2]])
      expect(result.offer_rank).to eq(2)
    end

    it 'offers only what the best match leads to, however the other hits rank' do
      brake_offer = promotion_chunk('Promotion: Diskon rem', products: [brake])
      own = promotion_chunk('Promotion: Gratis cek')
      promotion_chunk('Promotion: Diskon oli', products: [oil])

      expect(prompt.arrange(retrieval(brake_chunk, own, oil_chunk)).offer.chunk).to eq(brake_offer)
      expect(prompt.arrange(retrieval(own, oil_chunk)).offer.chunk).to eq(own)
    end

    it 'offers, of the promotions of the product, the one whose own chunk is ranked best, else the oldest' do
      oldest = promotion_chunk('Promotion: Diskon oli', products: [oil])
      ranked = promotion_chunk('Promotion: Oli gratis jasa', products: [oil])

      expect(prompt.arrange(retrieval(oil_chunk, hours, ranked)).offer.chunk).to eq(ranked)
      expect(prompt.arrange(retrieval(oil_chunk, hours)).offer.chunk).to eq(oldest)
    end

    it 'offers nothing when the best match leads to no promotion, even with a product of a promotion lower in the hits' do
      promotion_chunk('Promotion: Diskon oli', products: [oil])

      [retrieval(hours, oil_chunk), retrieval(brake_chunk, oil_chunk)].each do |result|
        expect(prompt.arrange(result)).to eq(result)
      end
    end

    it 'offers nothing and keeps the knowledge as it is when the session already mentioned the best ranked promotion' do
      mentioned = promotion_chunk('Promotion: Diskon oli', products: [oil])
      promotion_chunk('Promotion: Diskon rem', products: [brake])
      result = retrieval(oil_chunk, mentioned, brake_chunk)

      expect(described_class.new(ai_agent: ai_agent, mentioned_ids: [mentioned.chunkable_id]).arrange(result)).to eq(result)
    end

    it 'never offers a promotion that is not active today or has no chunk yet' do
      promotion_chunk('Promotion: Diskon oli lama', products: [oil], ends_on: Date.new(2026, 11, 24))
      promotion_chunk('Promotion: Diskon oli nanti', products: [oil], starts_on: Date.new(2026, 11, 26))
      create(:ai_agent_promotion, ai_agent: ai_agent, products: [oil])
      result = retrieval(oil_chunk)

      expect(prompt.arrange(result)).to eq(result)
    end

    it 'offers a new promotion only while the session mentioned fewer than the session limit' do
      offer = promotion_chunk('Promotion: Diskon oli', products: [oil])
      mentioned = create_list(:ai_agent_promotion, AiAgent::Promotion::SESSION_LIMIT, ai_agent: ai_agent).map(&:id)
      result = retrieval(oil_chunk)

      expect(described_class.new(ai_agent: ai_agent, mentioned_ids: mentioned.first(2)).arrange(result).offer.chunk).to eq(offer)
      expect(described_class.new(ai_agent: ai_agent, mentioned_ids: mentioned).arrange(result)).to eq(result)
    end

    it 'keeps each neighbor pointing at its match when the ranks move up' do
      offer = promotion_chunk('Promotion: Diskon oli', products: [oil])
      hits = [[offer, 0.3, nil], [oil_chunk, 0.2, nil], [hours, nil, 2]].map.with_index(1) do |(chunk, score, neighbor_of), rank|
        AiAgents::KnowledgeRetriever::Hit.new(chunk: chunk, rank: rank, score: score, neighbor_of: neighbor_of)
      end
      result = AiAgents::KnowledgeRetriever::Result.new(mode: 'keyword', embedding_model: nil, queries: ['oli'], hits: hits)

      expect(prompt.arrange(result).hits.map { |hit| [hit.chunk, hit.rank, hit.neighbor_of] })
        .to eq([[oil_chunk, 1, nil], [hours, 2, 1], [offer, 3, nil]])
    end
  end

  describe '.text' do
    let(:promotion) { promotion_chunk('Promotion: Diskon <b>oli</b>') }

    it 'gives the rules for a promotion in the knowledge' do
      expect(described_class.text(retrieval(hours, promotion))).to eq(described_class::KNOWLEDGE_INSTRUCTIONS)
    end

    it 'gives the rules and the escaped entry of an offer' do
      expect(described_class.text(prompt.arrange(retrieval(promotion, hours)))).to eq(
        "#{described_class::OFFER_INSTRUCTIONS}\n<promotion_offer>\n[2] Promotion: Diskon &lt;b&gt;oli&lt;/b&gt;\n</promotion_offer>"
      )
    end

    it 'gives nothing without a promotion' do
      expect(described_class.text(retrieval(hours))).to be_nil
    end
  end
end

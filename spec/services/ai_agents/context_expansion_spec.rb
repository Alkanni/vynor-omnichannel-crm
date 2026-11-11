require 'rails_helper'

RSpec.describe AiAgents::ContextExpansion do
  let(:ai_agent) { create(:ai_agent) }
  let(:guide) { create(:ai_agent_knowledge_source, ai_agent: ai_agent, title: 'Panduan') }
  let(:policy) { create(:ai_agent_knowledge_source, ai_agent: ai_agent, title: 'Kebijakan') }
  let(:faq) { create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent) }
  # Five chunks in the first section of the guide and two in the second, two in one section of the policy, and a Q&A.
  let!(:steps) { Array.new(5) { |index| create_chunk(guide, "Langkah #{index}", section: 0) } }
  let!(:costs) { Array.new(2) { |index| create_chunk(guide, "Biaya #{index}", section: 1) } }
  let!(:rules) { Array.new(2) { |index| create_chunk(policy, "Aturan #{index}", section: 0) } }
  let!(:answer) { create_chunk(faq, 'Q: Jam buka?') }

  def create_chunk(source, content, section: nil)
    ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: source, chunkable_updated_at: source.updated_at, content: content,
                                      section: section)
  end

  def expand(matches, radius:, limit: 20)
    described_class.new(chunks: ai_agent.knowledge_chunks.searchable(nil), matches: matches, radius: radius, limit: limit).perform
  end

  def sent(hits)
    hits.map { |hit| [hit.chunk.content, hit.rank, hit.score, hit.neighbor_of] }
  end

  it 'sends up to the radius of chunks before and after a match, only from its section of its source' do
    hits = expand([[steps[1], 0.5], [costs[0], 0.4]], radius: 2)

    expect(sent(hits)).to eq(
      [['Langkah 0', 1, nil, 2], ['Langkah 1', 2, 0.5, nil], ['Langkah 2', 3, nil, 2], ['Langkah 3', 4, nil, 2],
       ['Biaya 0', 5, 0.4, nil], ['Biaya 1', 6, nil, 5]]
    )
  end

  it 'sends a neighbor that is also a match once, as a match with its score' do
    hits = expand([[steps[2], 0.5], [steps[3], 0.4]], radius: 1)

    expect(sent(hits)).to eq(
      [['Langkah 1', 1, nil, 2], ['Langkah 2', 2, 0.5, nil], ['Langkah 3', 3, 0.4, nil], ['Langkah 4', 4, nil, 3]]
    )
  end

  it 'orders the runs of consecutive chunks by their best match, each in document order' do
    hits = expand([[rules[1], 0.5], [steps[4], 0.4], [steps[0], 0.3]], radius: 1)

    expect(sent(hits)).to eq(
      [['Aturan 0', 1, nil, 2], ['Aturan 1', 2, 0.5, nil], ['Langkah 3', 3, nil, 4], ['Langkah 4', 4, 0.4, nil],
       ['Langkah 0', 5, 0.3, nil], ['Langkah 1', 6, nil, 5]]
    )
  end

  it 'sends no neighbors for a Q&A entry or a chunk without a section' do
    steps[2].update!(section: nil)

    hits = expand([[answer, 0.5], [steps[2], 0.4]], radius: 3)

    expect(sent(hits)).to eq([['Q: Jam buka?', 1, 0.5, nil], ['Langkah 2', 2, 0.4, nil]])
  end

  describe 'with the context limit' do
    let(:matches) { [[steps[1], 0.5], [rules[0], 0.4], [answer, 0.3]] }

    it 'lets a neighbor of a match take the place of the match ranked NEIGHBOR_STEP lower per chunk of distance' do
      stub_const("#{described_class}::NEIGHBOR_STEP", 1)

      expect(sent(expand(matches, radius: 1, limit: 3))).to eq([['Langkah 1', 1, 0.5, nil], ['Langkah 2', 2, nil, 1], ['Aturan 0', 3, 0.4, nil]])
      expect(expand(matches, radius: 1, limit: 4).map { |hit| hit.chunk.content }).to eq(['Langkah 0', 'Langkah 1', 'Langkah 2', 'Aturan 0'])
    end

    it 'keeps the lower matches before the neighbors with a larger step' do
      stub_const("#{described_class}::NEIGHBOR_STEP", 2)

      expect(sent(expand(matches, radius: 1, limit: 3))).to eq([['Langkah 1', 1, 0.5, nil], ['Aturan 0', 2, 0.4, nil], ['Q: Jam buka?', 3, 0.3, nil]])
    end
  end
end

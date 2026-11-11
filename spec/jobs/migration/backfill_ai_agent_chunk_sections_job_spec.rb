require 'rails_helper'

RSpec.describe Migration::BackfillAiAgentChunkSectionsJob do
  let(:ai_agent) { create(:ai_agent) }
  let(:content) { "Pembuka.\n\n# Syarat\n\n#{(['kata'] * 400).join(' ')}\n\n# Biaya\n\nRp10.000" }

  # Chunks as the indexer stored them before chunks kept their section.
  def create_chunks(source, texts, version: source.updated_at)
    texts.map do |text|
      ai_agent.knowledge_chunks.create!(account: ai_agent.account, chunkable: source, chunkable_updated_at: version, content: text,
                                        embedding: Array.new(1536, 0.1), embedding_model: 'text-embedding-3-small')
    end
  end

  it 'gives the chunks of a source their sections when chunking it again makes the same chunks, keeping their embeddings' do
    source = create(:ai_agent_knowledge_source, ai_agent: ai_agent, content: content)
    chunks = create_chunks(source, AiAgents::KnowledgeIndexer.chunks(source).map(&:text))
    embeddings = chunks.map { |chunk| chunk.reload.embedding }
    allow(AiAgents::LlmClient).to receive(:new)

    described_class.perform_now

    expect(chunks.map { |chunk| chunk.reload.section }).to eq([0, 1, 1, 2])
    expect(chunks.map(&:embedding)).to eq(embeddings)
    expect(AiAgents::LlmClient).not_to have_received(:new)
  end

  it 'leaves the chunks without sections when they differ from a new chunking or come from an older version of the source' do
    changed = create(:ai_agent_knowledge_source, ai_agent: ai_agent, content: content)
    changed_chunks = create_chunks(changed, ["#{changed.title}\n\n#{content}"])
    outdated = create(:ai_agent_knowledge_source, ai_agent: ai_agent, content: content)
    outdated_chunks = create_chunks(outdated, AiAgents::KnowledgeIndexer.chunks(outdated).map(&:text), version: 1.day.ago)
    qa = create(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent)
    qa_chunks = create_chunks(qa, AiAgents::KnowledgeIndexer.chunks(qa).map(&:text))

    described_class.perform_now

    expect((changed_chunks + outdated_chunks + qa_chunks).map { |chunk| chunk.reload.section }).to all(be_nil)
  end
end

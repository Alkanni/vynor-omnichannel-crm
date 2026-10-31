require 'rails_helper'

RSpec.describe Migration::RechunkAiAgentsJob do
  let(:ai_agent) { create(:ai_agent) }
  let(:qa_agent) { create(:ai_agent) }
  let(:text) { create(:ai_agent_knowledge_source, ai_agent: ai_agent, content: "# Harga\n\nRoti Rp10.000") }
  let(:qa) { create(:ai_agent_knowledge_source, :qa, ai_agent: qa_agent) }

  before do
    [text, qa].each do |source|
      source.ai_agent.knowledge_chunks.create!(account: source.account, chunkable: source, chunkable_updated_at: source.updated_at,
                                               content: source.content, embedding_model: nil)
    end
    allow(Redis::Alfred).to receive(:set).and_return(true)
  end

  it 'schedules training only for agents with knowledge that chunks differently, keeping their chunks until it runs' do
    expect { described_class.perform_now }
      .to have_enqueued_job(AiAgents::IndexKnowledgeJob).with(ai_agent)
      .and have_enqueued_job(AiAgents::IndexKnowledgeJob).exactly(:once)

    expect(ai_agent.knowledge_chunks.count).to eq(1)
    expect(qa_agent.knowledge_chunks.sole.chunkable_updated_at).to eq(qa.updated_at)
  end

  it 'makes the indexer chunk the marked sources again and shows them as outdated until then' do
    described_class.perform_now

    expect(text.index_summary.status_for(text)).to eq('outdated')

    AiAgents::KnowledgeIndexer.new(ai_agent: ai_agent).perform

    expect(ai_agent.knowledge_chunks.sole.content).to eq("#{text.title}\n\nHarga\n\nRoti Rp10.000")
    expect(text.index_summary.status_for(text)).to eq('indexed')
  end

  it 'extracts DOCX files again, because their stored text lost its structure' do
    docx = create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :file, content: 'Teks lama', status: :ready, title: 'Panduan',
                                              file: fixture_file_upload('spec/assets/ai_agents/structured.docx'))
    pdf = create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :file, content: 'Teks PDF', status: :ready, title: 'Menu',
                                             file: fixture_file_upload('spec/assets/sample.pdf', 'application/pdf'))

    expect { described_class.perform_now }.to have_enqueued_job(AiAgents::ProcessKnowledgeSourceJob).with(docx).exactly(:once)

    expect(docx.reload).to be_pending
    expect(pdf.reload).to be_ready
  end
end

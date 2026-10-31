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

  context 'with an indexed DOCX file' do
    let(:docx) do
      create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :file, content: 'Teks lama', status: :ready, title: 'Panduan',
                                         file: fixture_file_upload('spec/assets/ai_agents/structured.docx'))
    end

    before do
      ai_agent.knowledge_chunks.create!(account: docx.account, chunkable: docx, chunkable_updated_at: docx.updated_at, content: 'Panduan lama',
                                        embedding_model: nil)
    end

    it 'extracts it again, because its stored text lost its structure, and leaves other files alone' do
      pdf = create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :file, content: 'Teks PDF', status: :ready, title: 'Menu',
                                               file: fixture_file_upload('spec/assets/sample.pdf', 'application/pdf'))

      described_class.perform_now
      AiAgents::KnowledgeIndexer.new(ai_agent: ai_agent).perform

      expect(docx.reload.content).to start_with('# Kebijakan toko')
      expect(ai_agent.knowledge_chunks.where(chunkable: docx).pluck(:content).join).to include('Kebijakan toko > Harga')
      expect(pdf.reload.content).to eq('Teks PDF')
    end

    it 'keeps it ready and its chunks in the index while it is extracted again' do
      during_extraction = nil
      allow(AiAgents::FileTextExtractor).to receive(:new) do
        AiAgents::KnowledgeIndexer.new(ai_agent: ai_agent).perform
        during_extraction = ai_agent.knowledge_chunks.where(chunkable: docx).count
        instance_double(AiAgents::FileTextExtractor, perform: '# Baru')
      end

      described_class.perform_now

      expect(during_extraction).to eq(1)
      expect(docx.reload).to be_ready
    end

    it 'leaves a file that cannot be read as it was and still schedules training' do
      docx
      version = docx.reload.updated_at
      allow(AiAgents::FileTextExtractor).to receive(:new).and_raise(AiAgents::ExtractionError, 'tidak terbaca')

      expect { described_class.perform_now }.to have_enqueued_job(AiAgents::IndexKnowledgeJob).with(ai_agent)

      expect(docx.reload).to have_attributes(status: 'ready', content: 'Teks lama', updated_at: version)
      AiAgents::KnowledgeIndexer.new(ai_agent: ai_agent).perform
      expect(ai_agent.knowledge_chunks.where(chunkable: docx).sole.content).to eq("Panduan\n\nTeks lama")
    end

    it 'leaves a file without text as it was' do
      allow(AiAgents::FileTextExtractor).to receive(:new).and_return(instance_double(AiAgents::FileTextExtractor, perform: ''))

      described_class.perform_now

      expect(docx.reload.content).to eq('Teks lama')
    end
  end
end

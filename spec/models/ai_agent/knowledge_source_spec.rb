require 'rails_helper'

RSpec.describe AiAgent::KnowledgeSource do
  let(:ai_agent) { create(:ai_agent) }

  it 'takes the account of its AI agent' do
    source = create(:ai_agent_knowledge_source, ai_agent: ai_agent)

    expect(source.account_id).to eq(ai_agent.account_id)
  end

  it 'validates text sources' do
    source = build(:ai_agent_knowledge_source, ai_agent: ai_agent, title: 'a' * 256, content: 'a' * 100_001)

    expect(source).not_to be_valid
    expect(source.errors.attribute_names).to contain_exactly(:title, :content)
  end

  it 'allows a text source without content' do
    expect(build(:ai_agent_knowledge_source, ai_agent: ai_agent, content: nil)).to be_valid
  end

  it 'validates question and answer pairs' do
    source = build(:ai_agent_knowledge_source, :qa, ai_agent: ai_agent, title: '', content: '')
    expect(source).not_to be_valid
    expect(source.errors.attribute_names).to contain_exactly(:title, :content)

    source.assign_attributes(title: 'a' * 1_001, content: 'a' * 5_001)
    expect(source).not_to be_valid
    expect(source.errors.attribute_names).to contain_exactly(:title, :content)
  end

  it 'rejects unknown source types with a validation error' do
    source = build(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: 'video')

    expect(source).not_to be_valid
    expect(source.errors.attribute_names).to eq([:source_type])
  end

  describe 'website sources' do
    it 'requires a unique http address per AI agent and starts pending' do
      source = create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, title: nil, content: nil,
                                                  external_url: 'https://grandsehat.example.com')

      expect(source).to have_attributes(status: 'pending', title: 'https://grandsehat.example.com')
      expect(build(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, external_url: source.external_url)).not_to be_valid
      expect(build(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, external_url: 'javascript:alert(1)')).not_to be_valid
    end

    it 'enqueues processing again on resync' do
      source = create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, title: nil, content: 'Old',
                                                  external_url: 'https://grandsehat.example.com', status: :failed)

      expect { source.resync! }.to have_enqueued_job(AiAgents::ProcessKnowledgeSourceJob).with(source)
      expect(source.reload).to be_pending
    end
  end

  describe 'file sources' do
    def file_source(io, filename, content_type)
      source = described_class.new(ai_agent: ai_agent, source_type: :file)
      source.file.attach(io: io, filename: filename, content_type: content_type)
      source
    end

    it 'accepts supported documents and names them after the file' do
      source = file_source(Rails.root.join('spec/assets/ai_agents/sample.docx').open, 'jadwal.docx',
                           'application/vnd.openxmlformats-officedocument.wordprocessingml.document')

      expect(source).to be_valid
      source.save!
      expect(source).to have_attributes(title: 'jadwal.docx', status: 'pending')
    end

    it 'rejects files whose content does not match the extension' do
      source = file_source(StringIO.new("MZ\x90\x00binary"), 'katalog.pdf', 'application/pdf')

      expect(source).not_to be_valid
      expect(source.errors.attribute_names).to eq([:file])
    end

    it 'rejects unsupported extensions and files over 100 MB' do
      expect(file_source(StringIO.new('a,b'), 'data.csv', 'text/csv')).not_to be_valid

      large = file_source(StringIO.new('teks'), 'besar.txt', 'text/plain')
      allow(large.file).to receive(:byte_size).and_return(100.megabytes + 1)
      expect(large).not_to be_valid
    end

    it 'does not allow files on other source types' do
      source = described_class.new(ai_agent: ai_agent, source_type: :text, title: 'Default')
      source.file.attach(io: StringIO.new('teks'), filename: 'a.txt', content_type: 'text/plain')

      expect(source).not_to be_valid
    end
  end

  it 'copies extracted content without processing it again' do
    source = create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, title: 'Layanan', content: 'Isi halaman',
                                                external_url: 'https://grandsehat.example.com', status: :ready)
    target = create(:ai_agent, account: ai_agent.account)

    expect { source.copy_to!(target) }.not_to have_enqueued_job(AiAgents::ProcessKnowledgeSourceJob)
    expect(target.knowledge_sources.website.first).to have_attributes(content: 'Isi halaman', status: 'ready', external_url: source.external_url)
  end
end

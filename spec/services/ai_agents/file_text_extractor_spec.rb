require 'rails_helper'

RSpec.describe AiAgents::FileTextExtractor do
  let(:ai_agent) { create(:ai_agent) }

  def source_with(path, content_type)
    source = AiAgent::KnowledgeSource.new(ai_agent: ai_agent, source_type: :file)
    source.file.attach(io: Rails.root.join(path).open, filename: File.basename(path), content_type: content_type)
    source.save!
    source
  end

  it 'extracts text from a PDF' do
    source = source_with('spec/assets/sample.pdf', 'application/pdf')

    expect(described_class.new(source.file).perform).to include('A Simple PDF File')
  end

  it 'stops reading PDF pages once the character limit is reached' do
    source = source_with('spec/assets/sample.pdf', 'application/pdf')
    stub_const('AiAgent::KnowledgeSource::MAX_EXTRACTED_CHARACTERS', 10)

    text = described_class.new(source.file).perform

    expect(text).to include('A Simple PDF File')
    expect(text).not_to include('Simple PDF File 2')
  end

  it 'returns no text for a PDF without a text layer' do
    source = source_with('spec/assets/ai_agents/blank.pdf', 'application/pdf')

    expect(described_class.new(source.file).perform.strip).to eq('')
  end

  it 'extracts paragraphs from a DOCX document' do
    source = source_with('spec/assets/ai_agents/sample.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')

    expect(described_class.new(source.file).perform).to eq("Grand Sehat buka setiap hari\npukul 07.30 - 18.00")
  end

  it 'extracts text from a Word 97-2003 document with antiword' do
    source = source_with('spec/assets/ai_agents/sample.doc', 'application/msword')
    allow(Open3).to receive(:capture2).with('antiword', '-w', '0', kind_of(String))
                                      .and_return(['Isi dokumen Word lama', instance_double(Process::Status, success?: true)])

    expect(described_class.new(source.file).perform).to eq('Isi dokumen Word lama')
  end

  it 'fails readably when antiword cannot read the document' do
    source = source_with('spec/assets/ai_agents/sample.doc', 'application/msword')
    allow(Open3).to receive(:capture2).and_return(['', instance_double(Process::Status, success?: false)])

    expect { described_class.new(source.file).perform }.to raise_error(AiAgents::ExtractionError, /could not be read/)
  end

  it 'reads text and markdown files as UTF-8' do
    source = AiAgent::KnowledgeSource.new(ai_agent: ai_agent, source_type: :file)
    source.file.attach(io: StringIO.new("\uFEFF# Jam buka\n07.30 - 18.00"), filename: 'info.md', content_type: 'text/markdown')
    source.save!

    expect(described_class.new(source.file).perform).to eq("# Jam buka\n07.30 - 18.00")
  end

  it 'fails readably for a damaged PDF' do
    source = AiAgent::KnowledgeSource.new(ai_agent: ai_agent, source_type: :file)
    source.file.attach(io: StringIO.new('%PDF-1.4 broken'), filename: 'broken.pdf', content_type: 'application/pdf')
    source.save!

    expect { described_class.new(source.file).perform }.to raise_error(AiAgents::ExtractionError)
  end
end

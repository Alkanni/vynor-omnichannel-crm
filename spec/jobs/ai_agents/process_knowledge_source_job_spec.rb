require 'rails_helper'

RSpec.describe AiAgents::ProcessKnowledgeSourceJob do
  let(:ai_agent) { create(:ai_agent) }
  let(:url) { 'https://grandsehat.example.com/layanan' }
  let(:page_html) do
    <<~HTML
      <html><head><title>Layanan Grand Sehat</title><script>var tracking = 1;</script></head>
      <body>
        <nav><a href="/">Beranda</a></nav>
        <main><h1>Layanan</h1><p>Spooring dan <strong>balancing</strong> mulai Rp 150.000.</p></main>
        <footer>Hak cipta</footer>
      </body></html>
    HTML
  end
  let(:website_source) { create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, title: nil, content: nil, external_url: url) }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('grandsehat.example.com').and_return(['93.184.216.34'])
  end

  it 'is enqueued when a website source is created' do
    expect { website_source }.to have_enqueued_job(described_class)
    expect(website_source).to be_pending
  end

  it 'stores the main content of the page as markdown' do
    stub_request(:get, url).to_return(status: 200, body: page_html, headers: { 'content-type' => 'text/html' })

    described_class.perform_now(website_source)

    expect(website_source.reload).to have_attributes(status: 'ready', title: 'Layanan Grand Sehat', error_message: nil)
    expect(website_source.content).to include('# Layanan', 'Spooring dan **balancing** mulai Rp 150.000.')
    expect(website_source.content).not_to include('Beranda', 'Hak cipta', 'tracking')
  end

  it 'keeps every item of listing pages without a main element' do
    listing = '<html><body><article><h3>Stabill</h3><img src="a.jpg" alt="foto"></article><article><h3>Balance arm</h3></article></body></html>'
    stub_request(:get, url).to_return(status: 200, body: listing, headers: { 'content-type' => 'text/html' })

    described_class.perform_now(website_source)

    expect(website_source.reload.content).to include('Stabill', 'Balance arm')
    expect(website_source.content).not_to include('a.jpg')
  end

  it 'marks the source as failed when the page cannot be loaded' do
    stub_request(:get, url).to_return(status: 404)

    described_class.perform_now(website_source)

    expect(website_source.reload).to have_attributes(status: 'failed', content: nil)
    expect(website_source.error_message).to include('could not be loaded')
  end

  it 'never fetches private addresses' do
    source = create(:ai_agent_knowledge_source, ai_agent: ai_agent, source_type: :website, title: nil, content: nil,
                                                external_url: 'http://169.254.169.254/latest/meta-data')

    described_class.perform_now(source)

    expect(source.reload).to have_attributes(status: 'failed', error_message: I18n.t('ai_agents.knowledge.errors.unsafe_url'))
    expect(a_request(:get, 'http://169.254.169.254/latest/meta-data')).not_to have_been_made
  end

  it 'truncates very long content and records it' do
    stub_request(:get, url).to_return(status: 200, body: "<html><body><p>#{'a' * 600_000}</p></body></html>",
                                      headers: { 'content-type' => 'text/html' })

    described_class.perform_now(website_source)

    expect(website_source.reload.content.length).to eq(AiAgent::KnowledgeSource::MAX_EXTRACTED_CHARACTERS)
    expect(website_source.metadata['truncated']).to be(true)
  end

  it 'marks a PDF without text as failed with guidance' do
    source = AiAgent::KnowledgeSource.new(ai_agent: ai_agent, source_type: :file)
    source.file.attach(io: Rails.root.join('spec/assets/ai_agents/blank.pdf').open, filename: 'scan.pdf', content_type: 'application/pdf')
    source.save!

    described_class.perform_now(source)

    expect(source.reload).to have_attributes(status: 'failed', error_message: I18n.t('ai_agents.knowledge.errors.no_text'))
  end

  it 'extracts the text of an uploaded file' do
    source = AiAgent::KnowledgeSource.new(ai_agent: ai_agent, source_type: :file)
    source.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'brosur.pdf', content_type: 'application/pdf')
    source.save!

    described_class.perform_now(source)

    expect(source.reload).to have_attributes(status: 'ready', title: 'brosur.pdf')
    expect(source.content).to include('A Simple PDF File')
  end

  it 'reports unexpected errors and marks the source as failed' do
    stub_request(:get, url).to_return(status: 200, body: page_html, headers: { 'content-type' => 'text/html' })
    allow(ReverseMarkdown).to receive(:convert).and_raise(StandardError, 'boom')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now(website_source)

    expect(website_source.reload).to have_attributes(status: 'failed', error_message: I18n.t('ai_agents.knowledge.errors.processing_failed'))
    expect(tracker).to have_received(:capture_exception)
  end
end

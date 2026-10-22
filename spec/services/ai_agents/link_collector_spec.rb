require 'rails_helper'

RSpec.describe AiAgents::LinkCollector do
  let(:start_url) { 'https://grandsehat.example.com/' }
  let(:page_html) do
    <<~HTML
      <html><body>
        <a href="/layanan">Layanan</a>
        <a href="/layanan#harga">Harga</a>
        <a href="https://grandsehat.example.com/kontak/">Kontak</a>
        <a href="/brosur.pdf">Brosur</a>
        <a href="https://other.example.com/page">Other site</a>
        <a href="mailto:cs@grandsehat.example.com">Email</a>
      </body></html>
    HTML
  end
  let(:sitemap_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>https://grandsehat.example.com/promo</loc></url>
        <url><loc>https://grandsehat.example.com/layanan</loc></url>
      </urlset>
    XML
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('grandsehat.example.com').and_return(['93.184.216.34'])
    stub_request(:get, start_url).to_return(status: 200, body: page_html, headers: { 'content-type' => 'text/html; charset=utf-8' })
  end

  it 'collects unique links of the same host from the sitemap and the page, without files' do
    stub_request(:get, 'https://grandsehat.example.com/sitemap.xml')
      .to_return(status: 200, body: sitemap_xml, headers: { 'content-type' => 'application/xml' })

    expect(described_class.new(start_url).perform).to eq(
      %w[
        https://grandsehat.example.com
        https://grandsehat.example.com/promo
        https://grandsehat.example.com/layanan
        https://grandsehat.example.com/kontak
      ]
    )
  end

  it 'still collects page links when there is no sitemap' do
    stub_request(:get, 'https://grandsehat.example.com/sitemap.xml').to_return(status: 404)

    expect(described_class.new(start_url).perform).to include('https://grandsehat.example.com/layanan')
  end

  it 'stops at 300 links' do
    many_links = (1..400).map { |n| "<a href=\"/halaman-#{n}\">#{n}</a>" }.join
    stub_request(:get, start_url).to_return(status: 200, body: "<html><body>#{many_links}</body></html>", headers: { 'content-type' => 'text/html' })
    stub_request(:get, 'https://grandsehat.example.com/sitemap.xml').to_return(status: 404)

    expect(described_class.new(start_url).perform.size).to eq(300)
  end

  it 'rejects addresses that are not http or https' do
    expect { described_class.new('ftp://grandsehat.example.com') }.to raise_error(AiAgents::ExtractionError)
  end

  %w[http://127.0.0.1/ http://169.254.169.254/latest/meta-data http://10.0.0.1/].each do |private_url|
    it "never fetches the private address #{private_url}" do
      expect { described_class.new(private_url).perform }.to raise_error(AiAgents::ExtractionError, /private or local network/)
      expect(a_request(:get, private_url)).not_to have_been_made
    end
  end
end

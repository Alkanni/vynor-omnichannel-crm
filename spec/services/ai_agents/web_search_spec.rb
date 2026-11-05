require 'rails_helper'

RSpec.describe AiAgents::WebSearch do
  let(:url) { 'https://api.exa.ai/search' }
  let(:api_key) { 'exa-secret-key' }
  let(:query) { 'penyebab mesin mobil overheat' }
  let(:exa_results) do
    [{ id: 'a', title: 'Mesin overheat', url: 'https://otomotif.example/overheat', publishedDate: '2026-10-01T03:00:00.000Z', author: nil,
       highlights: ['Radiator tersumbat membuat mesin panas.'], highlightScores: [0.5] },
     { id: 'b', title: 'Cek radiator', url: 'https://bengkel.example/radiator', publishedDate: nil, highlights: ['Periksa air radiator.'] }]
  end
  let(:exa_response) do
    { status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { requestId: 'req-1', results: exa_results, costDollars: { total: 0.004, search: { neural: 0.004 } } }.to_json }
  end
  let(:spend_key) { "ai_agents:web_search:spend:#{Time.now.utc.strftime('%Y-%m')}" }

  before do
    create(:installation_config, name: 'AI_AGENT_EXA_API_KEY', value: api_key)
    keys = []
    Redis::Alfred.scan_each(match: 'ai_agents:web_search:*') { |key| keys << key }
    keys.each { |key| Redis::Alfred.delete(key) }
  end

  it 'searches Exa with the agreed request and returns the normalized results' do
    request = stub_request(:post, url).with(
      headers: { 'x-api-key' => api_key, 'Content-Type' => 'application/json' },
      body: { query: query, type: 'lite', numResults: 3, userLocation: 'ID', contents: { highlights: { maxCharacters: 800 } } }.to_json
    ).to_return(exa_response)

    result = described_class.new(query: query).perform

    expect(request).to have_been_made.once
    expect(result).to have_attributes(status: 'searched', cost_usd: 0.004, latency_ms: be >= 0)
    expect(result.results.map(&:to_h)).to eq(
      [{ rank: 1, title: 'Mesin overheat', url: 'https://otomotif.example/overheat', published_at: Date.new(2026, 10, 1),
         highlights: ['Radiator tersumbat membuat mesin panas.'] },
       { rank: 2, title: 'Cek radiator', url: 'https://bengkel.example/radiator', published_at: nil, highlights: ['Periksa air radiator.'] }]
    )
  end

  it 'gives a prompt the highlights of a result as one text of at most 800 characters' do
    item = described_class::Item.new(rank: 1, title: 'Mesin overheat', url: 'https://otomotif.example/overheat', published_at: nil,
                                     highlights: ["Radiator  tersumbat.\n" * 60, 'Kipas mati.'])

    expect(item.text.length).to be <= 800
    expect(item.text).to start_with('Radiator tersumbat. Radiator tersumbat.').and end_with('...')
    expect(item.with(highlights: ['Radiator tersumbat.', 'Kipas mati.']).text).to eq('Radiator tersumbat. Kipas mati.')
  end

  it 'searches only the given domains' do
    request = stub_request(:post, url).with(body: hash_including(includeDomains: ['otomotif.example'])).to_return(exa_response)

    described_class.new(query: query, domains: ['otomotif.example']).perform

    expect(request).to have_been_made.once
  end

  it 'opens the connection within 1 second and reads the answer within 4' do
    stub_request(:post, url).to_return(exa_response)
    connections = []
    allow(Faraday).to receive(:new).and_wrap_original do |method, *args, **options, &block|
      method.call(*args, **options, &block).tap { |connection| connections << connection }
    end

    described_class.new(query: query).perform

    expect(connections.sole.options).to have_attributes(open_timeout: 1, read_timeout: 4)
  end

  it 'returns searched with no results when Exa finds nothing' do
    stub_request(:post, url).to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                       body: { results: [], costDollars: { total: 0.004 } }.to_json)

    expect(described_class.new(query: query).perform).to have_attributes(status: 'searched', results: [])
  end

  it 'returns a failed status without raising when Exa times out, limits the rate, or has an error' do
    { 'failed_timeout' => [->(stub) { stub.to_timeout }, ->(stub) { stub.to_raise(Net::ReadTimeout) }],
      'failed_rate_limit' => [->(stub) { stub.to_return(status: 429) }],
      'failed_provider' => [->(stub) { stub.to_return(status: 500) }, ->(stub) { stub.to_return(status: 503) },
                            ->(stub) { stub.to_raise(Errno::ECONNREFUSED) }] }.each do |status, failures|
      failures.each do |failure|
        failure.call(stub_request(:post, url))

        expect(described_class.new(query: query).perform).to have_attributes(status: status, results: [], cost_usd: 0)
      end
    end
    expect(Redis::Alfred.get(spend_key)).to be_nil
  end

  it 'reports a rejected request to the exception tracker without the key' do
    log = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log))
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original

    [400, 401, 403].each do |code|
      stub_request(:post, url).to_return(status: code, headers: { 'Content-Type' => 'application/json' },
                                         body: { requestId: 'req-1', error: "Invalid API key #{api_key}", tag: 'INVALID_API_KEY' }.to_json)

      expect(described_class.new(query: query).perform).to have_attributes(status: 'failed_request', results: [])
      expect(ChatwootExceptionTracker).to have_received(:new)
        .with(having_attributes(class: described_class::RequestError, message: "Exa rejected the web search request (HTTP #{code}, INVALID_API_KEY)"))
    end
    expect(log.string).to include('HTTP 401')
    expect(log.string).not_to include(api_key)
  end

  it 'adds what Exa charged to the spend of the month in micro-dollars' do
    stub_request(:post, url).to_return(exa_response)

    travel_to(Time.utc(2026, 11, 30, 23, 0)) do
      2.times { |index| described_class.new(query: "#{query} #{index}").perform }

      expect(Redis::Alfred.get('ai_agents:web_search:spend:2026-11')).to eq('8000')
      expect(Redis::Alfred.ttl('ai_agents:web_search:spend:2026-11')).to eq(40.days.to_i)
    end
  end

  it 'does not call Exa once the spend of the month reaches the budget' do
    request = stub_request(:post, url).to_return(exa_response)
    create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_MONTHLY_BUDGET', value: '0.01')
    Redis::Alfred.set(spend_key, 9_999)

    expect(described_class.new(query: query).perform).to have_attributes(status: 'searched')

    expect(described_class.new(query: "#{query} lagi").perform)
      .to have_attributes(status: 'skipped_budget', results: [], latency_ms: nil, cost_usd: 0)
    expect(request).to have_been_made.once
  end

  it 'keeps the budget at 8 US dollars when it is blank' do
    expect(described_class.monthly_budget).to eq(8)

    create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_MONTHLY_BUDGET', value: '')
    expect(described_class.monthly_budget).to eq(8)
  end

  it 'stops calling Exa after a 402 until the next UTC month' do
    request = stub_request(:post, url).to_return(status: 402, headers: { 'Content-Type' => 'application/json' },
                                                 body: { error: 'Out of credits', tag: 'NO_MORE_CREDITS' }.to_json)

    travel_to(Time.utc(2026, 11, 30, 23, 0)) do
      expect(described_class.new(query: query).perform).to have_attributes(status: 'failed_credits')
      expect(described_class.new(query: query).perform).to have_attributes(status: 'skipped_budget')
    end
    expect(request).to have_been_made.once

    travel_to(Time.utc(2026, 12, 1, 0, 1)) { described_class.new(query: query).perform }
    expect(request).to have_been_made.twice
  end

  it 'answers the same search from the cache for 6 hours without a request or spend' do
    request = stub_request(:post, url).to_return(exa_response)
    searched = travel_to(Time.utc(2026, 11, 4, 8, 0)) { described_class.new(query: query).perform }

    cached = travel_to(Time.utc(2026, 11, 4, 13, 59)) { described_class.new(query: query).perform }

    expect(cached).to have_attributes(status: 'cached', results: searched.results, latency_ms: nil, cost_usd: 0)
    expect(request).to have_been_made.once
    expect(Redis::Alfred.get('ai_agents:web_search:spend:2026-11')).to eq('4000')

    travel_to(Time.utc(2026, 11, 4, 14, 1)) { described_class.new(query: query).perform }
    expect(request).to have_been_made.twice
  end

  it 'caches each set of domains on its own' do
    request = stub_request(:post, url).to_return(exa_response)

    described_class.new(query: query).perform
    expect(described_class.new(query: query, domains: ['otomotif.example']).perform).to have_attributes(status: 'searched')
    expect(request).to have_been_made.twice
  end
end

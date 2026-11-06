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
    create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_API_KEY', value: api_key)
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
        .with(having_attributes(class: described_class::RequestError,
                                message: "Web search provider exa rejected the request (HTTP #{code}, INVALID_API_KEY)"))
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

  describe 'with another provider' do
    let(:json) { { 'Content-Type' => 'application/json' } }
    let(:domains) { ['otomotif.example', 'bengkel.example'] }

    it 'searches Tavily with its request and counts 1 credit at the pay-as-you-go price' do
      create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_PROVIDER', value: 'tavily')
      request = stub_request(:post, 'https://api.tavily.com/search').with(
        headers: { 'Authorization' => "Bearer #{api_key}", 'Content-Type' => 'application/json' },
        body: { query: query, search_depth: 'basic', max_results: 3, country: 'indonesia', include_published_date: true,
                include_domains: domains }.to_json
      ).to_return(status: 200, headers: json, body: {
        query: query, response_time: 0.9, request_id: 'req-1',
        results: [{ title: 'Mesin overheat', url: 'https://otomotif.example/overheat', content: 'Radiator tersumbat membuat mesin panas.',
                    score: 0.8, published_date: 'Thu, 01 Oct 2026 03:00:00 GMT' },
                  { title: 'Cek radiator', url: 'https://bengkel.example/radiator', content: 'Periksa air radiator.', published_date: nil }]
      }.to_json)

      travel_to(Time.utc(2026, 11, 6, 8, 0)) do
        result = described_class.new(query: query, domains: domains).perform

        expect(request).to have_been_made.once
        expect(result).to have_attributes(status: 'searched', cost_usd: 0.008)
        expect(result.results.map(&:to_h)).to eq(
          [{ rank: 1, title: 'Mesin overheat', url: 'https://otomotif.example/overheat', published_at: Date.new(2026, 10, 1),
             highlights: ['Radiator tersumbat membuat mesin panas.'] },
           { rank: 2, title: 'Cek radiator', url: 'https://bengkel.example/radiator', published_at: nil, highlights: ['Periksa air radiator.'] }]
        )
        expect(Redis::Alfred.get('ai_agents:web_search:spend:2026-11')).to eq('8000')
      end
    end

    it 'searches Brave with the domains as site: operators and turns its HTML into text' do
      create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_PROVIDER', value: 'brave')
      request = stub_request(:get, 'https://api.search.brave.com/res/v1/web/search').with(
        headers: { 'X-Subscription-Token' => api_key, 'Accept' => 'application/json' },
        query: { q: "#{query} site:otomotif.example OR site:bengkel.example", count: '3', country: 'ID' }
      ).to_return(status: 200, headers: json, body: {
        type: 'search',
        web: { results: [{ title: 'Mesin <strong>overheat</strong>', url: 'https://otomotif.example/overheat',
                           description: 'Radiator &amp; kipas <strong>rusak</strong> bikin mesin&#x27;s panas.', page_age: '2026-10-01T03:00:00' },
                         { title: 'Cek radiator', url: 'https://bengkel.example/radiator' }] }
      }.to_json)

      result = described_class.new(query: query, domains: domains).perform

      expect(request).to have_been_made.once
      expect(result).to have_attributes(status: 'searched', cost_usd: 0.005)
      expect(result.results.map(&:to_h)).to eq(
        [{ rank: 1, title: 'Mesin overheat', url: 'https://otomotif.example/overheat', published_at: Date.new(2026, 10, 1),
           highlights: ["Radiator & kipas rusak bikin mesin's panas."] },
         { rank: 2, title: 'Cek radiator', url: 'https://bengkel.example/radiator', published_at: nil, highlights: [] }]
      )
    end

    it 'returns searched with no results when Brave finds nothing' do
      create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_PROVIDER', value: 'brave')
      stub_request(:get, 'https://api.search.brave.com/res/v1/web/search').with(query: { q: query, count: '3', country: 'ID' })
                                                                          .to_return(status: 200, headers: json, body: { type: 'search' }.to_json)

      expect(described_class.new(query: query).perform).to have_attributes(status: 'searched', results: [], cost_usd: 0.005)
    end

    it 'searches Perplexity with its request' do
      create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_PROVIDER', value: 'perplexity')
      request = stub_request(:post, 'https://api.perplexity.ai/search').with(
        headers: { 'Authorization' => "Bearer #{api_key}", 'Content-Type' => 'application/json' },
        body: { query: query, max_results: 3, max_tokens_per_page: 256, country: 'ID', search_domain_filter: domains }.to_json
      ).to_return(status: 200, headers: json, body: {
        id: 'req-1',
        results: [{ title: 'Mesin overheat', url: 'https://otomotif.example/overheat', snippet: 'Radiator tersumbat membuat mesin panas.',
                    date: '2026-10-01', last_updated: '2026-10-02' }]
      }.to_json)

      result = described_class.new(query: query, domains: domains).perform

      expect(request).to have_been_made.once
      expect(result).to have_attributes(status: 'searched', cost_usd: 0.005)
      expect(result.results.map(&:to_h)).to eq(
        [{ rank: 1, title: 'Mesin overheat', url: 'https://otomotif.example/overheat', published_at: Date.new(2026, 10, 1),
           highlights: ['Radiator tersumbat membuat mesin panas.'] }]
      )
    end

    it 'stops searching a provider whose credits are gone, but not the other providers' do
      provider = create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_PROVIDER', value: 'tavily')
      tavily = stub_request(:post, 'https://api.tavily.com/search').to_return(status: 432, headers: json,
                                                                              body: { detail: { error: 'Plan limit exceeded' } }.to_json)
      exa = stub_request(:post, url).to_return(exa_response)

      expect(described_class.new(query: query).perform).to have_attributes(status: 'failed_credits', results: [], cost_usd: 0)
      expect(described_class.new(query: query).perform).to have_attributes(status: 'skipped_budget')
      expect(tavily).to have_been_made.once

      provider.update!(value: 'exa')
      expect(described_class.new(query: query).perform).to have_attributes(status: 'searched')
      expect(exa).to have_been_made.once
    end

    it 'tells credits that are gone from too many searches by the answer of each provider' do
      { 'tavily' => [[:post, 'https://api.tavily.com/search', { status: 433 }, 'failed_credits'],
                     [:post, 'https://api.tavily.com/search', { status: 429 }, 'failed_rate_limit']],
        'brave' => [[:get, %r{\Ahttps://api\.search\.brave\.com/}, { status: 429, body: { error: { code: 'CREDIT_EXHAUSTED' } } }, 'failed_credits'],
                    [:get, %r{\Ahttps://api\.search\.brave\.com/}, { status: 429, body: { error: { code: 'RATE_LIMITED' } } }, 'failed_rate_limit']],
        'perplexity' => [[:post, 'https://api.perplexity.ai/search', { status: 402 }, 'failed_credits'],
                         [:post, 'https://api.perplexity.ai/search', { status: 429 }, 'failed_rate_limit']] }.each do |name, answers|
        config = InstallationConfig.find_or_initialize_by(name: 'AI_AGENT_WEB_SEARCH_PROVIDER')
        config.update!(value: name)
        answers.each do |verb, endpoint, answer, status|
          Redis::Alfred.delete("ai_agents:web_search:credits_gone:#{name}:#{Time.now.utc.strftime('%Y-%m')}")
          stub_request(verb, endpoint).to_return(status: answer[:status], headers: json, body: answer.fetch(:body, {}).to_json)

          expect(described_class.new(query: query).perform).to have_attributes(status: status, results: [])
        end
      end
    end

    it 'reports the error code of a rejected Brave request without the key' do
      create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_PROVIDER', value: 'brave')
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original
      stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/}).to_return(
        status: 422, headers: json, body: { error: { code: 'SUBSCRIPTION_TOKEN_INVALID', detail: "Invalid token #{api_key}" } }.to_json
      )

      expect(described_class.new(query: query).perform).to have_attributes(status: 'failed_request')
      expect(ChatwootExceptionTracker).to have_received(:new).with(
        having_attributes(message: 'Web search provider brave rejected the request (HTTP 422, SUBSCRIPTION_TOKEN_INVALID)')
      )
    end

    it 'does not answer a provider from the cache of another' do
      provider = create(:installation_config, name: 'AI_AGENT_WEB_SEARCH_PROVIDER', value: 'perplexity')
      perplexity = stub_request(:post, 'https://api.perplexity.ai/search')
                   .to_return(status: 200, headers: json, body: { id: 'req-1', results: [] }.to_json)
      exa = stub_request(:post, url).to_return(exa_response)

      described_class.new(query: query).perform
      provider.update!(value: 'exa')
      expect(described_class.new(query: query).perform).to have_attributes(status: 'searched')
      provider.update!(value: 'perplexity')
      expect(described_class.new(query: query).perform).to have_attributes(status: 'cached')

      expect(perplexity).to have_been_made.once
      expect(exa).to have_been_made.once
    end
  end
end

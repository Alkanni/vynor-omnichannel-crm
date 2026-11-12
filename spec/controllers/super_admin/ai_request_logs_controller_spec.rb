require 'rails_helper'

RSpec.describe 'Super Admin AI request logs', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:ai_agent) { create(:ai_agent) }
  let(:account) { ai_agent.account }
  let(:other_ai_agent) { create(:ai_agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:customer_message) { '<script>alert(1)</script> berapa harga kopi susu?' }
  let(:prompt) { "Kamu adalah asisten Toko Kopi.\n\n#{"Jawab hanya dari knowledge.\n" * 800}" }
  let(:steps) do
    [
      { step: 'scope_check', started_ms: 0, latency_ms: 300, model: 'gpt-scope', tokens: { input: 100, output: 10, cached_input: 0 },
        input: { temperature: 0.0, instructions: 'Decide the scope.', messages: [{ role: 'user', content: customer_message }],
                 schema: 'ai_agent_scope' },
        output: { 'decision' => 'in_scope', 'web_query' => 'harga kopi susu' } },
      { step: 'embedding', started_ms: 300, latency_ms: 50, model: 'embed-model', input: { input_type: 'query', texts: ['query: harga kopi susu'] },
        output: { vectors: 1, dimensions: 1536 } },
      { step: 'retrieval', started_ms: 350, latency_ms: 20, input: { mode: 'hybrid', queries: ['harga kopi susu'] },
        output: { hits: [{ rank: 1, chunk_id: 7, chunkable_type: 'AiAgent::KnowledgeSource', chunkable_id: 3, score: 0.0325, distance: 0.2134,
                           neighbor_of: nil, content: 'Kopi susu Rp18.000 per gelas' }] } },
      { step: 'web_search', started_ms: 370, latency_ms: 900, input: { provider: 'tavily', query: 'harga kopi susu', domains: nil },
        output: { status: 'ok', latency_ms: 880, cost_usd: 0.008,
                  results: [{ rank: 1, title: 'Daftar harga kopi', url: 'https://example.com/kopi', text: 'Harga kopi hari ini' }] } },
      { step: 'reply', started_ms: 1270, latency_ms: 2000, model: 'gpt-reply', tokens: { input: 6000, output: 40, cached_input: nil },
        input: { temperature: 0.4, instructions: prompt, messages: [{ role: 'user', content: customer_message }], schema: 'ai_agent_reply' },
        output: { 'messages' => ['Kopi susu harganya Rp18.000 kak'], 'handoff' => false } },
      { step: 'reply_check', started_ms: 3270, latency_ms: 5, input: { sources: ['knowledge'] },
        output: { decision: 'allowed', blocked_reason: nil } },
      { step: 'watcher', started_ms: 3275, latency_ms: 700, model: 'gpt-watch', tokens: { input: 900, output: 20, cached_input: 0 },
        input: { temperature: 0.0, instructions: 'Check the handoff.', messages: [], schema: 'ai_agent_watch' },
        output: { 'handoff' => false, 'labels' => ['harga'] } }
    ]
  end
  let!(:reply_log) do
    AiAgent::RequestLog.create!(account: account, ai_agent: ai_agent, source: :reply, status: :ok, latency_ms: 3975, conversation: conversation,
                                reply_trace_id: 42, created_at: Time.utc(2026, 11, 12, 10), steps: steps,
                                input: { messages: [{ role: 'user', content: customer_message, attachments: [] }] },
                                output: { messages: ['Kopi susu harganya Rp18.000 kak'], handoff: false, labels: [], sheet_row: nil })
  end
  let!(:watcher_log) do
    AiAgent::RequestLog.create!(account: account, ai_agent: ai_agent, source: :watcher, status: :ok, latency_ms: 700,
                                created_at: Time.utc(2026, 11, 11, 10), conversation: create(:conversation, account: account))
  end
  let!(:playground_log) do
    AiAgent::RequestLog.create!(account: other_ai_agent.account, ai_agent: other_ai_agent, source: :playground, status: :error,
                                error_class: 'Faraday::TimeoutError', latency_ms: 30_000, created_at: Time.utc(2026, 11, 9, 10),
                                input: { messages: [{ role: 'user', content: 'halo' }] })
  end

  describe 'access' do
    it 'sends a visitor who is not signed in as a Super Admin to the Super Admin login' do
      sign_in(create(:user, account: account, role: :administrator))

      get '/super_admin/ai_request_logs'
      expect(response).to redirect_to('/super_admin/sign_in')

      get "/super_admin/ai_request_logs/#{reply_log.id}"
      expect(response).to redirect_to('/super_admin/sign_in')
    end
  end

  describe 'GET /super_admin/ai_request_logs' do
    let(:listed_ids) do
      -> { Nokogiri::HTML(response.body).css('tbody tr td:first-child a').map { |link| link['href'].split('/').last.to_i } }
    end

    before { sign_in(super_admin, scope: :super_admin) }

    it 'lists the runs newest first without loading their steps' do
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "ai_agent_request_logs"') }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { get '/super_admin/ai_request_logs' }

      expect(response).to have_http_status(:success)
      expect(listed_ids.call).to eq([reply_log, watcher_log, playground_log].map(&:id))
      rows = Nokogiri::HTML(response.body).css('tbody tr').map { |row| row.css('td').map { |cell| cell.text.squish } }
      expect(rows.values_at(0, 2)).to eq(
        [['2026-11-12 10:00:00', account.name, ai_agent.name, 'reply', "##{conversation.display_id}", 'ok', '3975 ms', '7,070', customer_message],
         ['2026-11-09 10:00:00', other_ai_agent.account.name, other_ai_agent.name, 'playground', '—', 'error', '30000 ms', '—', 'halo']]
      )
      expect(response.body).to include("href=\"/app/accounts/#{account.id}/conversations/#{conversation.display_id}\"")
      expect(response.body).not_to include('Jawab hanya dari knowledge.')
      expect(queries).not_to be_empty
      expect(queries.grep(/"ai_agent_request_logs"\.(\*|"steps")/)).to be_empty
    end

    it 'narrows the list with each filter' do
      {
        { account_id: account.id } => [reply_log, watcher_log],
        { ai_agent_id: other_ai_agent.id } => [playground_log],
        { source: 'watcher' } => [watcher_log],
        { status: 'error' } => [playground_log],
        { conversation: conversation.display_id, account_id: account.id } => [reply_log],
        { from: '2026-11-11' } => [reply_log, watcher_log],
        { to: '2026-11-10' } => [playground_log],
        { from: '2026-11-11', to: '2026-11-11' } => [watcher_log]
      }.each do |filters, logs|
        get '/super_admin/ai_request_logs', params: filters
        expect(listed_ids.call).to eq(logs.map(&:id)), "#{filters} listed #{listed_ids.call}"
      end
    end

    it 'shows 25 runs per page' do
      newer = Array.new(25) do |minutes|
        AiAgent::RequestLog.create!(account: account, ai_agent: ai_agent, source: :reply, status: :ok,
                                    created_at: Time.utc(2026, 11, 13) + minutes.minutes)
      end

      get '/super_admin/ai_request_logs'
      expect(listed_ids.call).to eq(newer.reverse.map(&:id))

      get '/super_admin/ai_request_logs', params: { page: 2 }
      expect(listed_ids.call).to eq([reply_log, watcher_log, playground_log].map(&:id))
    end

    it 'rejects a date that is not YYYY-MM-DD' do
      get '/super_admin/ai_request_logs', params: { from: 'kemarin' }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'escapes the content of the logs' do
      get '/super_admin/ai_request_logs'

      expect(response.body).not_to include('<script>alert(1)</script>')
      expect(response.body).to include('&lt;script&gt;alert(1)&lt;/script&gt;')
    end

    context 'when there are no logs' do
      before { AiAgent::RequestLog.delete_all }

      it 'says that the AI Agents record nothing while the request log is off' do
        get '/super_admin/ai_request_logs'

        expect(response.body).to include('There are no request logs yet.')
        expect(response.body).to include('only while AI_AGENT_REQUEST_LOG_ENABLED is on, and it is off')
      end

      it 'says that the next run will appear while the request log is on' do
        create(:installation_config, name: 'AI_AGENT_REQUEST_LOG_ENABLED', value: 'true')

        get '/super_admin/ai_request_logs'

        expect(response.body).to include('AI_AGENT_REQUEST_LOG_ENABLED is on, so the next run of an AI Agent will appear here')
      end

      it 'says that no logs match the filters' do
        get '/super_admin/ai_request_logs', params: { source: 'reply' }

        expect(response.body).to include('No request logs match these filters.')
      end
    end
  end

  describe 'GET /super_admin/ai_request_logs/:id' do
    let(:document) { Nokogiri::HTML(response.body) }

    before { sign_in(super_admin, scope: :super_admin) }

    it 'shows each step in order with its input and output' do
      get "/super_admin/ai_request_logs/#{reply_log.id}"

      expect(response).to have_http_status(:success)
      expect(document.css('.main-content__body details > summary').map { |summary| summary.text.squish.split.second }).to eq(steps.pluck(:step))
      texts = document.css('pre').map(&:text)
      expect(texts).to include(prompt, 'Decide the scope.', 'Check the handoff.', 'Kopi susu Rp18.000 per gelas', 'Harga kopi hari ini', 'allowed',
                               JSON.pretty_generate(['query: harga kopi susu']), JSON.pretty_generate(['Kopi susu harganya Rp18.000 kak']))
      expect(response.body).to include('https://example.com/kopi', 'Daftar harga kopi', '0.2134', '6000 input, 40 output, — cached input')
      expect(response.body).to include("href=\"/app/accounts/#{account.id}/conversations/#{conversation.display_id}\"")
      expect(document.text.squish).to include('Reply trace ID 42')
      expect(response.body).not_to include('<script>alert(1)</script>')
    end

    it 'shows a run that raised with its error and no output' do
      get "/super_admin/ai_request_logs/#{playground_log.id}"

      expect(response).to have_http_status(:success)
      expect(document.text.squish).to include('error Faraday::TimeoutError', 'This run has no steps.')
    end
  end
end

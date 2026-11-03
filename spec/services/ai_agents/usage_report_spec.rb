require 'rails_helper'

RSpec.describe AiAgents::UsageReport do
  let(:ai_agent) { create(:ai_agent, name: 'CS Toko Roti', model: 'gpt-4.1-mini') }
  let(:conversations) { create_list(:conversation, 3, account: ai_agent.account) }
  let(:in_period) { Time.utc(2026, 11, 3, 5) }
  let(:report) { described_class.new(from: Time.utc(2026, 11, 1), to: Time.utc(2026, 11, 8)).perform }

  before do
    # A strict reply with a Watcher run, and a scope reply, in a conversation without a handoff.
    create(:ai_agent_reply_trace, ai_agent: ai_agent, conversation: conversations[0], created_at: in_period, scope_decision: 'IN_SCOPE',
                                  scope_input_tokens: 900, scope_output_tokens: 5, input_tokens: 2400, output_tokens: 65, cached_input_tokens: 100,
                                  latency_ms: 3000, scope_latency_ms: 1200, retrieved: Array.new(3) { |index| { 'rank' => index + 1 } },
                                  reply_decision: 'answer',
                                  watcher_input_tokens: 300, watcher_output_tokens: 8, watcher_cached_input_tokens: 0)
    create(:ai_agent_reply_trace, ai_agent: ai_agent, conversation: conversations[0], created_at: in_period, scope_decision: 'OUT_OF_SCOPE',
                                  scope_input_tokens: 900, scope_output_tokens: 5, input_tokens: 900, output_tokens: 5, latency_ms: 1300,
                                  scope_latency_ms: 1300)
    create(:ai_agent_reply_trace, ai_agent: ai_agent, conversation: conversations[1], created_at: in_period, status: :handoff,
                                  scope_decision: 'HANDOFF_REQUEST', scope_input_tokens: 950, scope_output_tokens: 5, input_tokens: 2500,
                                  output_tokens: 50, cached_input_tokens: 0, latency_ms: 4000, retrieved: [{ 'rank' => 1 }, { 'rank' => 2 }],
                                  reply_decision: 'conversational')
    # A strict reply from before the scope check had token columns of its own, then a failed reply.
    create(:ai_agent_reply_trace, ai_agent: ai_agent, conversation: conversations[2], created_at: in_period, scope_decision: 'IN_SCOPE',
                                  input_tokens: 2900, output_tokens: 70, latency_ms: 3500,
                                  retrieved: Array.new(3) { |index| { 'rank' => index + 1 } })
    create(:ai_agent_reply_trace, ai_agent: ai_agent, conversation: conversations[2], created_at: in_period, status: :error,
                                  error_class: 'AiAgents::LlmError')
    create(:ai_agent_reply_trace, ai_agent: ai_agent, created_at: Time.utc(2026, 10, 20), input_tokens: 99_999)
  end

  it 'sums up the model calls, tokens, latency, decisions, and conversations of each agent in the period' do
    expect(report.lines(chomp: true)).to include(
      '# AI Agent usage from 2026-11-01T00:00:00Z to 2026-11-08T00:00:00Z',
      "## CS Toko Roti (id #{ai_agent.id})",
      '- Traces by status: error 1, handoff 1, replied 3',
      '- Models: gpt-4.1-mini 5',
      '| Scope check | 4 | total 2750, p50 900, p90 950 (n=3) | total 15, p50 5, p90 5 (n=3) |',
      '| Reply model | 3 | total 3050, p50 1500, p90 1550 (n=2) | total 105, p50 45, p90 60 (n=2) |',
      '| Watcher | 1 | total 300, p50 300, p90 300 (n=1) | total 8, p50 8, p90 8 (n=1) |',
      '- Cached input tokens of the scope check and reply model: 100 of 5000 input tokens (2%, n=2)',
      '- Cached input tokens of the Watcher: 0 of 300 input tokens (0%, n=1)',
      '- Reply latency in ms (scope check, knowledge search, and reply model): p50 3000, p95 4000 (n=4)',
      '- Scope check latency in ms: p50 1200, p95 1300 (n=2)',
      '- Knowledge chunks sent per reply model call: p50 3, p90 3 (n=3)',
      '- Scope check decisions: HANDOFF_REQUEST 1, IN_SCOPE 2, OUT_OF_SCOPE 1',
      '- Reply decisions: answer 1, conversational 1',
      '- Conversations: 3, without a handoff: 1 (33%)',
      '- Tokens per conversation: total 9298, p50 2970, p90 3778 (n=3)',
      '- Model calls per conversation: p50 2, p90 4 (n=3)',
      '- Tokens per conversation without a handoff: total 3778, p50 3778, p90 3778 (n=1)',
      '- Model calls per conversation without a handoff: p50 4, p90 4 (n=1)'
    )
  end

  it 'reports every agent with traces in the period, or the one asked for' do
    other_agent = create(:ai_agent, name: 'CS Bengkel')
    create(:ai_agent_reply_trace, ai_agent: other_agent, created_at: in_period, input_tokens: 700, output_tokens: 20)

    expect(report).to include("## CS Toko Roti (id #{ai_agent.id})", "## CS Bengkel (id #{other_agent.id})")
    single = described_class.new(from: Time.utc(2026, 11, 1), to: Time.utc(2026, 11, 8), ai_agent_id: other_agent.id).perform
    expect(single).to include('| Reply model | 1 | total 700, p50 700, p90 700 (n=1) |')
    expect(single).not_to include('CS Toko Roti')
    expect(described_class.new(from: Time.utc(2026, 9, 1), to: Time.utc(2026, 9, 8), ai_agent_id: other_agent.id).perform)
      .to end_with("## CS Bengkel (id #{other_agent.id})\n\nNo reply traces.")
  end

  it 'says when the gateway reported no cached input' do
    AiAgent::ReplyTrace.find_each { |trace| trace.update!(cached_input_tokens: nil, watcher_input_tokens: nil) }

    expect(report).to include('- Cached input tokens of the scope check and reply model: not reported',
                              '- Cached input tokens of the Watcher: not reported', '| Watcher | 0 | n/a | n/a |')
  end
end

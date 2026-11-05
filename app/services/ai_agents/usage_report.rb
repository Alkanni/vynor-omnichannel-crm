# Sums up how the AI Agents used their models over a period, from their reply traces (see AiAgent::ReplyTrace), as Markdown
# for the ai_agents:usage_report task. Per agent: the traces by status, the model calls and their tokens by kind, cached
# input, latency, the knowledge chunks sent, the decisions, web search for an agent with it, and the tokens and model
# calls per conversation, also for the conversations the AI handled without a handoff. Counts only, without message,
# knowledge, or web content.
# A model call is counted when it returned, since a failed one ends in an error trace; Watcher calls are counted by their
# tokens. Statistics leave out the traces that lack their columns, such as those written before the columns existed, and
# say over how many values they were taken (n).
class AiAgents::UsageReport
  # A conversation without a handoff has a reply trace in the period and none with these statuses.
  HANDOFF_STATUSES = %w[handoff message_limit error].freeze

  pattr_initialize [:from!, :to!, :ai_agent_id]

  def perform
    lines = ["# AI Agent usage from #{from.utc.iso8601} to #{to.utc.iso8601}"]
    agents.each { |ai_agent| lines.push('', *agent_report(ai_agent)) }
    lines.join("\n")
  end

  private

  def agents
    return [AiAgent.find(ai_agent_id)] if ai_agent_id

    AiAgent.where(id: traces.select(:ai_agent_id)).order(:id)
  end

  def traces
    AiAgent::ReplyTrace.where(created_at: from...to)
  end

  def agent_report(ai_agent)
    rows = traces.where(ai_agent: ai_agent).order(:id).to_a
    title = "## #{ai_agent.name} (id #{ai_agent.id})"
    return [title, '', 'No reply traces.'] if rows.empty?

    [title, '', "- Traces by status: #{counts(rows.map(&:status))}", "- Models: #{counts(rows.map(&:model))}", '',
     *call_table(rows), '', *cached_lines(rows), *detail_lines(rows), *web_lines(rows), *conversation_lines(rows)]
  end

  def call_table(rows)
    ['| Model call | Calls | Input tokens | Output tokens |', '|---|---|---|---|',
     call_row('Scope check', rows.select(&:scope_decision).map { |row| [row.scope_input_tokens, row.scope_output_tokens] }),
     call_row('Reply model', rows.select { |row| reply_model?(row) }.map { |row| reply_tokens(row) }),
     call_row('Watcher', rows.select(&:watcher_input_tokens).map { |row| [row.watcher_input_tokens, row.watcher_output_tokens] })]
  end

  # tokens holds the [input, output] tokens of each call, nil where the trace lacks them.
  def call_row(name, tokens)
    input_tokens, output_tokens = tokens.transpose
    "| #{name} | #{tokens.size} | #{stats(Array(input_tokens), total: true)} | #{stats(Array(output_tokens), total: true)} |"
  end

  def cached_lines(rows)
    ["- Cached input tokens of the scope check and reply model: #{cached_share(rows.map { |row| [row.input_tokens, row.cached_input_tokens] })}",
     "- Cached input tokens of the Watcher: #{cached_share(rows.map { |row| [row.watcher_input_tokens, row.watcher_cached_input_tokens] })}"]
  end

  def detail_lines(rows)
    reply_calls = rows.select { |row| reply_model?(row) }
    ["- Reply latency in ms (scope check, knowledge search, web search, and reply model): #{stats(rows.map(&:latency_ms), percentiles: [50, 95])}",
     "- Scope check latency in ms: #{stats(rows.map(&:scope_latency_ms), percentiles: [50, 95])}",
     "- Knowledge chunks sent per reply model call: #{stats(reply_calls.map { |row| row.retrieved.size })}",
     "- Scope check decisions: #{counts(rows.filter_map(&:scope_decision))}",
     "- Reply decisions: #{counts(rows.filter_map(&:reply_decision))}"]
  end

  # The turns with web search (see AiAgents::ReplyGenerator::Trace#web_search_status): the share that needed the web, what
  # became of them, and the requests made to Exa.
  def web_lines(rows)
    web_rows = rows.select(&:web_search_status)
    return [] if web_rows.empty?

    routed = web_rows.count { |row| row.web_search_status != 'not_needed' }
    ["- Turns routed to web search: #{routed} of #{web_rows.size} turns with web search (#{(routed * 100.0 / web_rows.size).round}%)",
     "- Web search statuses: #{counts(web_rows.map(&:web_search_status))}", *exa_lines(web_rows.select(&:web_latency_ms))]
  end

  # requests: the traces of the turns whose search made a request to Exa.
  def exa_lines(requests)
    ["- Exa requests: #{requests.size}, spend US$#{format('%.3f', requests.sum(&:web_cost_usd))}",
     "- Exa request latency in ms: #{stats(requests.map(&:web_latency_ms), percentiles: [50, 95])}"]
  end

  def conversation_lines(rows)
    conversations = rows.group_by(&:conversation_id).values
    without_handoff = conversations.select do |conversation|
      conversation.any?(&:replied?) && conversation.none? { |row| HANDOFF_STATUSES.include?(row.status) }
    end
    ["- Conversations: #{conversations.size}, without a handoff: #{without_handoff.size} " \
     "(#{(without_handoff.size * 100.0 / conversations.size).round}%)",
     *per_conversation('conversation', conversations), *per_conversation('conversation without a handoff', without_handoff)]
  end

  def per_conversation(name, conversations)
    ["- Tokens per #{name}: #{stats(conversations.map { |rows| tokens(rows) }, total: true)}",
     "- Model calls per #{name}: #{stats(conversations.map { |rows| rows.sum { |row| model_calls(row) } })}"]
  end

  # A reply or handoff that the scope check did not answer itself.
  def reply_model?(row)
    (row.replied? || row.handoff?) && !AiAgents::ScopeGuard::REPLY_ATTRIBUTES.key?(row.scope_decision)
  end

  def model_calls(row)
    [row.scope_decision.present?, reply_model?(row), row.watcher_input_tokens.present?].count(true)
  end

  # The reply model's share of a trace's [input, output] tokens: all of them without a scope check, and nil when the scope
  # check ran but its share is unknown.
  def reply_tokens(row)
    return [row.input_tokens, row.output_tokens] unless row.scope_decision

    [[row.input_tokens, row.scope_input_tokens], [row.output_tokens, row.scope_output_tokens]].map { |total, scope| total - scope if total && scope }
  end

  # Input, cached input, and output of all model calls of a conversation's traces, the Watcher's included; nil when none
  # reported usage.
  def tokens(rows)
    rows.flat_map do |row|
      [row.input_tokens, row.cached_input_tokens, row.output_tokens, row.watcher_input_tokens, row.watcher_cached_input_tokens,
       row.watcher_output_tokens]
    end.compact.presence&.sum
  end

  # pairs are [input tokens, cached input tokens] per trace; only the traces whose gateway reported both count.
  def cached_share(pairs)
    reported = pairs.select(&:all?)
    return 'not reported' if reported.empty?

    cached = reported.sum(&:last)
    whole = reported.sum(&:sum)
    "#{cached} of #{whole} input tokens (#{(cached * 100.0 / whole).round}%, n=#{reported.size})"
  end

  # Nearest-rank percentiles of the values that are not nil.
  def stats(values, percentiles: [50, 90], total: false)
    sorted = values.compact.sort
    return 'n/a' if sorted.empty?

    parts = percentiles.map { |percentile| "p#{percentile} #{sorted[(sorted.size * percentile / 100.0).ceil - 1]}" }
    parts.unshift("total #{sorted.sum}") if total
    "#{parts.join(', ')} (n=#{sorted.size})"
  end

  def counts(values)
    values.tally.sort.map { |value, count| "#{value} #{count}" }.join(', ').presence || 'none'
  end
end

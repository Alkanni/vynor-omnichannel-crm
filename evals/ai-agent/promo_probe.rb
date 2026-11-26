# Live probe of the promotion limits of a conversation session (issue #215), which the playground cannot test because
# it has no conversation. It writes customer messages to an API inbox of the agent and lets Sidekiq reply as it does
# live, then reads each reply's trace, the prompt in its request log, and the promotion marked on its bubbles. Run it in
# the app container of a throwaway clone with the request log on (AI_AGENT_REQUEST_LOG_ENABLED), against the `promo`
# agent of fixtures/bengkel-promo.json:
#   PROBE_AGENT_ID=<id> bundle exec rails runner promo_probe.rb
# It creates an inbox, a contact, and conversations in the agent's account, and sets the agent's Message Await to 0.
# Session 1 asks about products with a promotion until the session mentioned AiAgent::Promotion::SESSION_LIMIT of them,
# then about one more and "ada promo apa saja?"; the conversation is resolved, the customer writes again (session 2), and
# then opens a new conversation (session 3). The checks:
# - one promotion at most in each prompt;
# - an offer only of a promotion the session has not mentioned;
# - once the session mentioned SESSION_LIMIT promotions, none other in a prompt;
# - the marker of each reply is the promotion it cites, when it passed the check;
# - a new session (after resolve, or a new conversation) starts with none mentioned, so its first promotion is offered.
class PromoProbe
  REPLY_TIMEOUT = 150
  SESSION_ONE = [
    'Berapa harga oli mesin 5W-30 4 liter?', 'Kalau aki kering 45Ah harganya berapa?', 'Oli 5W-30 4 liter itu stoknya ada?',
    'Kampas rem depan Avanza harganya berapa?', 'Ada promo untuk kampas rem depan Avanza?', 'Ada promo untuk aki kering?'
  ].freeze
  AFTER_LIMIT = ['Saya juga mau servis berkala, biayanya berapa?', 'Ada promo apa saja?'].freeze
  # What one reply had and did: the promotion of its prompt (a trace entry), whether it was offered and cited, the
  # promotion marked on its bubbles, and what the session had mentioned before it.
  Turn = Data.define(:session, :text, :mentioned, :promotion, :offered, :cited, :marker, :trace, :replies) do
    def promotion_id = promotion&.dig('chunkable_id')
  end
  PROMOTION_MARKER = AiAgents::ConversationSession::PROMOTION_MARKER

  def initialize(agent)
    @agent = agent
    @turns = []
    @failures = []
  end

  def perform
    @agent.update!(message_await: 0)
    first_session
    second_session
    third_session
    report
  end

  private

  def first_session
    @first = new_conversation
    SESSION_ONE.each { |text| turn(1, @first, text) if mentioned(@first).size < AiAgent::Promotion::SESSION_LIMIT }
    reached = mentioned(@first).size
    check(reached == AiAgent::Promotion::SESSION_LIMIT, "session 1 mentioned #{reached} promotions, so the limit was not reached")
    AFTER_LIMIT.each { |text| turn(1, @first, text) }
    check(mentioned(@first).size <= AiAgent::Promotion::SESSION_LIMIT, "session 1 mentioned #{mentioned(@first).size} promotions")
  end

  def second_session
    @first.resolved!
    wait_for { ReportingEvent.exists?(conversation_id: @first.id, name: 'conversation_resolved') }
    check(mentioned(@first).empty?, 'session 2 started with promotions mentioned')
    check(turn(2, @first, SESSION_ONE.first).offered, 'session 2 did not offer the promotion of session 1 again')
    check(@first.reload.pending?, 'the resolved conversation did not go back to pending')
  end

  def third_session
    second = new_conversation
    check(turn(3, second, SESSION_ONE.second).offered, 'a new conversation of the same customer did not offer its promotion')
  end

  def inbox
    @inbox ||= @agent.account.inboxes.find_by(name: 'Eval promo probe') ||
               @agent.account.inboxes.create!(name: 'Eval promo probe', channel: Channel::Api.create!(account: @agent.account))
  end

  def contact_inbox
    @contact_inbox ||= begin
      AiAgentInbox.find_or_create_by!(ai_agent: @agent, inbox: inbox)
      contact = @agent.account.contacts.create!(name: "Eval promo probe #{Time.current.to_i}")
      ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
    end
  end

  def new_conversation
    Conversation.create!(account: @agent.account, inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox).tap do |conversation|
      check(conversation.pending?, "conversation #{conversation.id} did not start pending")
    end
  end

  def mentioned(conversation)
    ActiveRecord::Base.uncached { AiAgents::ConversationSession.new(conversation: conversation.reload, ai_agent: @agent).promotion_ids }
  end

  def turn(session, conversation, text)
    before = mentioned(conversation)
    message = conversation.messages.create!(account: @agent.account, inbox: inbox, message_type: :incoming, sender: contact_inbox.contact,
                                            content: text)
    replies = wait_for { replies_to(conversation, message).presence }
    trace = wait_for { @agent.reply_traces.find_by(message: message) }
    record(Turn.new(session: session, text: text, mentioned: before, promotion: prompt_promotion(trace), offered: offered?(trace),
                    cited: cited?(trace), marker: replies.map { |reply| reply.additional_attributes[PROMOTION_MARKER] }.uniq,
                    trace: trace, replies: replies.map(&:content)))
  end

  def replies_to(conversation, message)
    conversation.messages.where(sender: @agent).where("additional_attributes ->> 'ai_agent_reply_to' = ?", message.id.to_s).to_a
  end

  def prompt_promotion(trace) = prompt_promotions(trace).first

  def prompt_promotions(trace) = Array(trace.retrieved).select { |hit| hit['chunkable_type'] == AiAgent::Promotion.name }

  def offered?(trace)
    promotion = prompt_promotion(trace)
    promotion.present? && reply_instructions(trace).include?("<promotion_offer>\n[#{promotion['rank']}]")
  end

  def cited?(trace) = prompt_promotion(trace).present? && Array(trace.cited_ranks).include?(prompt_promotion(trace)['rank'])

  # The instructions of the last reply model call of the trace's run.
  def reply_instructions(trace)
    AiAgent::RequestLog.find_by!(reply_trace_id: trace.id).steps.reverse.find { |step| step['step'] == 'reply' }&.dig('input', 'instructions').to_s
  end

  def record(turn)
    check(prompt_promotions(turn.trace).size <= 1, "#{turn.text}: more than one promotion in the prompt")
    check(!turn.offered || turn.mentioned.exclude?(turn.promotion_id), "#{turn.text}: offered promotion #{turn.promotion_id} again")
    check(within_limit?(turn), "#{turn.text}: promotion #{turn.promotion_id} past the session limit")
    expected = expected_marker(turn)
    check(turn.marker == [expected], "#{turn.text}: marked #{turn.marker.inspect}, expected #{expected.inspect}")
    @turns << turn
    turn
  end

  def within_limit?(turn)
    turn.mentioned.size < AiAgent::Promotion::SESSION_LIMIT || turn.promotion_id.nil? || turn.mentioned.include?(turn.promotion_id)
  end

  def expected_marker(turn)
    turn.promotion_id if turn.cited && turn.trace.blocked_reason.nil? && turn.trace.reply_decision != 'knowledge_gap'
  end

  def check(condition, failure)
    @failures << failure unless condition
  end

  # rails runner caches queries, so each poll reads past the cache.
  def wait_for(&)
    deadline = REPLY_TIMEOUT.seconds.from_now
    loop do
      found = ActiveRecord::Base.uncached(&)
      return found if found
      raise "timed out after #{REPLY_TIMEOUT}s" if Time.current > deadline

      sleep 2
    end
  end

  def report
    puts '| Session | Customer | Mentioned before | Promotion in prompt | Placement | Cited | Check | Reply |'
    puts '|---|---|---|---|---|---|---|---|'
    @turns.each { |turn| puts "| #{row(turn).join(' | ')} |" }
    puts
    puts(@failures.empty? ? 'PROBE PASS: all checks held' : "PROBE FAIL:\n- #{@failures.join("\n- ")}")
  end

  def row(turn)
    [turn.session, turn.text, turn.mentioned.join(', '), *promotion_cells(turn), turn.cited ? 'yes' : 'no',
     turn.trace.blocked_reason || turn.trace.reply_decision, turn.replies.join(' / ').tr("\n", ' ')]
  end

  # The title of the promotion in the prompt and its placement.
  def promotion_cells(turn)
    return %w[- -] unless turn.promotion_id

    [AiAgent::Promotion.find_by(id: turn.promotion_id)&.title, turn.offered ? 'offer' : 'knowledge']
  end
end

abort 'Turn AI_AGENT_REQUEST_LOG_ENABLED on first: the probe reads each prompt from the request log' unless AiAgents::RequestRecorder.enabled?

PromoProbe.new(AiAgent.find(ENV.fetch('PROBE_AGENT_ID'))).perform

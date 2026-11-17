# Records what goes into and comes out of each step of an AI Agent run as an AiAgent::RequestLog while
# AI_AGENT_REQUEST_LOG_ENABLED is on. Each entry point opens its run with .record (AiAgents::ReplyJob, AiAgents::WatchJob, the
# playground and Retrieval Test, and AiAgents::KnowledgeIndexer), and the services add their steps with .step as it runs:
# AiAgents::LlmClient for every model and query embedding call, AiAgents::KnowledgeRetriever, AiAgents::WebSearch, and
# AiAgents::ReplyValidator. A step inside another step is part of it and is not recorded on its own. Without an open run,
# .step only runs its block.
# Nothing is serialized before the run ends. The log is then written once, also for a run that raised, and a log that cannot
# be written is reported without changing anything else, so recording never alters a reply, a handoff, or a trace. With
# AI_AGENT_REQUEST_LOG_MASK_PII on, phone numbers and e-mail addresses are replaced in every text the log keeps; what the
# models get stays as it was.
class AiAgents::RequestRecorder
  CURRENT = :ai_agents_request_recorder
  PII_PLACEHOLDERS = {
    # Indonesian mobile numbers (0812…, 62812…, +62 812…) and any number written with a leading + (+1 415…), also with spaces,
    # dots, dashes, or parentheses between the digits.
    /(?<![\w+])(?:(?:\+?62|0)[\s.-]?8|\+\d)(?:[\s.()-]?\d){7,13}(?!\d)/ => '[phone]',
    /[[:alnum:]._%+-]+@[[:alnum:]-]+(?:\.[[:alnum:]-]+)+/ => '[email]'
  }.freeze

  # What the block of a step adds: its output and, for a model call, the tokens it used.
  Step = Struct.new(:output, :tokens)

  attr_writer :output

  class << self
    # links: the conversation_id, message_id, and reply_trace_id of the run, when it has them. Yields the recorder, whose
    # output the block sets, and returns what the block returns.
    def record(ai_agent:, source:, input:, **links, &)
      recorder = new(ai_agent: ai_agent, source: source, input: input, links: links)
      enabled? ? recorder.run(&) : yield(recorder)
    end

    # model: the model of a model or embedding call. Yields the Step and returns what the block returns.
    def step(name, input, model: nil, &)
      recorder = ActiveSupport::IsolatedExecutionState[CURRENT]
      recorder ? recorder.step(name, input, model, &) : yield(Step.new)
    end

    def enabled? = boolean_setting('AI_AGENT_REQUEST_LOG_ENABLED')
    def mask_pii? = boolean_setting('AI_AGENT_REQUEST_LOG_MASK_PII')

    private

    # Super Admin saves boolean settings as text.
    def boolean_setting(name) = ActiveModel::Type::Boolean.new.cast(AiAgents::LlmClient.setting(name)) || false
  end

  def initialize(ai_agent:, source:, input:, links:)
    @ai_agent = ai_agent
    @source = source
    @input = input
    @links = links
    @steps = []
  end

  # For a run whose trace is made while it runs (see AiAgents::ReplyJob).
  def reply_trace_id=(id)
    @links[:reply_trace_id] = id
  end

  def run
    previous = ActiveSupport::IsolatedExecutionState[CURRENT]
    ActiveSupport::IsolatedExecutionState[CURRENT] = self
    @started_at = now_ms
    yield self
  rescue StandardError => e
    @error_class = e.class.name
    raise
  ensure
    ActiveSupport::IsolatedExecutionState[CURRENT] = previous
    save
  end

  def step(name, input, model, &)
    @in_step ? yield(Step.new) : record_step(name, input, model, &)
  end

  private

  def record_step(name, input, model)
    @in_step = true
    step = Step.new
    started_at = now_ms
    yield step
  rescue StandardError => e
    error_class = e.class.name
    raise
  ensure
    @in_step = false
    @steps << { step: name, started_ms: started_at - @started_at, latency_ms: now_ms - started_at, input: input, output: step.output,
                model: model, tokens: step.tokens, error_class: error_class }
  end

  def save
    @mask = self.class.mask_pii?
    AiAgent::RequestLog.create!(account_id: @ai_agent.account_id, ai_agent: @ai_agent, source: @source, status: @error_class ? :error : :ok,
                                error_class: @error_class, latency_ms: now_ms - @started_at, input: json(@input), output: json(@output || {}),
                                steps: json(@steps), **@links)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @ai_agent.account).capture_exception
  end

  def json(value)
    case value
    when Hash then value.to_h { |key, item| [key.to_s, json(item)] }
    when Array then value.map { |item| json(item) }
    when String then masked(value)
    when RubyLLM::Content, ActiveStorage::Blob then json(reference(value))
    else value.as_json
    end
  end

  def masked(text)
    @mask ? PII_PLACEHOLDERS.reduce(text) { |result, (pattern, placeholder)| result.gsub(pattern, placeholder) } : text
  end

  # A message with images, or an image, as references to their blobs, never their content.
  def reference(value)
    return { text: value.text, attachments: value.attachments.map(&:source) } if value.is_a?(RubyLLM::Content)

    { blob_id: value.id, filename: value.filename.to_s, content_type: value.content_type, byte_size: value.byte_size }
  end

  def now_ms
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
  end
end

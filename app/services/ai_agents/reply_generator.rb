# Builds the LLM request for an AI Agent (behavior, local time, relevant knowledge, actions, history) and returns
# the reply as chat bubbles plus the actions it takes and a trace of how it was made.
# Messages are { role: :user | :assistant, content:, attachments: }.
class AiAgents::ReplyGenerator
  TEMPERATURES = { 'precise' => 0.2, 'balanced' => 0.5, 'creative' => 0.8 }.freeze
  MAX_REPLY_MESSAGES = 5
  MESSAGES_PROPERTY = { messages: { type: 'array', items: { type: 'string' } } }.freeze
  Reply = Data.define(:messages, :handoff, :labels, :sheet_row, :trace) do
    def initialize(messages:, handoff:, labels:, trace:, sheet_row: nil)
      super
    end
  end
  # retrieval is an AiAgents::KnowledgeRetriever::Result; latency_ms covers the knowledge search and the model call.
  Trace = Data.define(:retrieval, :input_tokens, :output_tokens, :latency_ms) do
    # The AiAgent::ReplyTrace columns it fills; chunks are kept as references, without their content.
    def attributes
      retrieved = retrieval.hits.map do |hit|
        { chunk_id: hit.chunk.id, chunkable_type: hit.chunk.chunkable_type, chunkable_id: hit.chunk.chunkable_id, rank: hit.rank, score: hit.score }
      end
      { retrieval_mode: retrieval.mode, embedding_model: retrieval.embedding_model, retrieved: retrieved,
        input_tokens: input_tokens, output_tokens: output_tokens, latency_ms: latency_ms }
    end
  end
  KNOWLEDGE_INSTRUCTIONS = <<~TEXT.freeze
    Use the knowledge below to answer. State facts such as prices, stock, schedules, and policies only when they appear
    in the knowledge or in the conversation. If the knowledge does not cover the question, say that you do not know.
  TEXT
  NO_RELEVANT_KNOWLEDGE_INSTRUCTIONS = <<~TEXT.freeze
    None of your knowledge is relevant to this message. State facts such as prices, stock, schedules, and policies only
    when they appear in the conversation; otherwise say that you do not know.
  TEXT
  RESPONSE_INSTRUCTIONS = <<~TEXT.freeze
    Put your reply in the "messages" array. Each item is sent to the customer as a separate chat bubble,
    so use more than one item only when separate bubbles help, and never more than #{MAX_REPLY_MESSAGES}.
  TEXT

  # written_rows: the Google Sheets rows already written for the conversation (see AiAgents::ActionSchema).
  pattr_initialize [:ai_agent!, :messages!, :written_rows]

  def perform
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    completion = client.chat(model: ai_agent.model, temperature: TEMPERATURES.fetch(ai_agent.temperature), instructions: instructions,
                             messages: llm_messages, schema: actions.json_schema('ai_agent_reply', MESSAGES_PROPERTY))
    content = completion.content
    content = {} unless content.is_a?(Hash)
    reply = Reply.new(messages: reply_messages(content), **actions.parse(content), trace: trace(completion, started_at))
    # A silent handoff may come without a note; any other turn needs something to send.
    raise AiAgents::LlmError, I18n.t('ai_agents.llm.errors.empty_reply') if reply.messages.empty? && !reply.handoff

    reply
  end

  private

  def trace(completion, started_at)
    Trace.new(retrieval: retrieval, input_tokens: completion.input_tokens, output_tokens: completion.output_tokens,
              latency_ms: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - started_at)
  end

  def reply_messages(content)
    Array(content['messages']).grep(String).map(&:strip).compact_blank.first(MAX_REPLY_MESSAGES)
  end

  def instructions
    [ai_agent.behavior.presence, current_time, knowledge, actions.instructions, RESPONSE_INSTRUCTIONS].compact.join("\n\n")
  end

  def current_time
    "Current date and time: #{Time.current.in_time_zone(ai_agent.timezone).strftime('%A, %-d %B %Y %H:%M')} (#{ai_agent.timezone})"
  end

  # An agent with knowledge but none relevant to the message still gets the rule against stating facts it was not given.
  def knowledge
    if retrieval.hits.empty?
      NO_RELEVANT_KNOWLEDGE_INSTRUCTIONS if ai_agent.knowledge_chunks.exists?
    else
      entries = retrieval.hits.map { |hit| "[#{hit.rank}] #{hit.chunk.content}" }
      "#{KNOWLEDGE_INSTRUCTIONS}\n<knowledge>\n#{entries.join("\n\n")}\n</knowledge>"
    end
  end

  def retrieval
    @retrieval ||= AiAgents::KnowledgeRetriever.new(ai_agent: ai_agent, messages: messages).perform
  end

  def llm_messages
    messages.map do |message|
      attachments = message[:attachments].presence
      { role: message[:role], content: attachments ? RubyLLM::Content.new(message[:content], attachments) : message[:content] }
    end
  end

  def actions
    @actions ||= AiAgents::ActionSchema.new(ai_agent: ai_agent, written_rows: written_rows)
  end

  def client
    @client ||= AiAgents::LlmClient.new
  end
end

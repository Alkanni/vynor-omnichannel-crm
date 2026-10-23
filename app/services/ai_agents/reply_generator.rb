# Builds the LLM request for an AI Agent (behavior, local time, relevant knowledge, history) and returns
# the reply as a list of chat bubbles. Messages are { role: :user | :assistant, content:, attachments: }.
class AiAgents::ReplyGenerator
  TEMPERATURES = { 'precise' => 0.2, 'balanced' => 0.5, 'creative' => 0.8 }.freeze
  MAX_REPLY_MESSAGES = 5
  MAX_QUERY_CHARACTERS = 4_000
  RESPONSE_SCHEMA = {
    name: 'ai_agent_reply',
    schema: {
      type: 'object',
      properties: { messages: { type: 'array', items: { type: 'string' } } },
      required: ['messages'],
      additionalProperties: false
    }
  }.freeze
  KNOWLEDGE_INSTRUCTIONS = <<~TEXT.freeze
    Use the knowledge below to answer. State facts such as prices, stock, schedules, and policies only when they appear
    in the knowledge or in the conversation. If the knowledge does not cover the question, say that you do not know.
  TEXT
  RESPONSE_INSTRUCTIONS = <<~TEXT.freeze
    Put your reply in the "messages" array. Each item is sent to the customer as a separate chat bubble,
    so use more than one item only when separate bubbles help, and never more than #{MAX_REPLY_MESSAGES}.
  TEXT

  pattr_initialize [:ai_agent!, :messages!]

  def perform
    content = client.chat(model: ai_agent.model, temperature: TEMPERATURES.fetch(ai_agent.temperature),
                          instructions: instructions, messages: llm_messages, schema: RESPONSE_SCHEMA)
    replies = content.is_a?(Hash) ? Array(content['messages']).grep(String).map(&:strip).compact_blank : []
    raise AiAgents::LlmError, I18n.t('ai_agents.llm.errors.empty_reply') if replies.empty?

    replies.first(MAX_REPLY_MESSAGES)
  end

  private

  def instructions
    [ai_agent.behavior.presence, current_time, knowledge, RESPONSE_INSTRUCTIONS].compact.join("\n\n")
  end

  def current_time
    "Current date and time: #{Time.current.in_time_zone(ai_agent.timezone).strftime('%A, %-d %B %Y %H:%M')} (#{ai_agent.timezone})"
  end

  def knowledge
    chunks = relevant_chunks
    return if chunks.empty?

    entries = chunks.map.with_index(1) { |chunk, index| "[#{index}] #{chunk.content}" }
    "#{KNOWLEDGE_INSTRUCTIONS}\n<knowledge>\n#{entries.join("\n\n")}\n</knowledge>"
  end

  def relevant_chunks
    query = latest_customer_text
    return [] if query.blank? || !ai_agent.knowledge_chunks.exists?

    embedding = client.embed([query]).first
    ai_agent.knowledge_chunks.nearest_neighbors(:embedding, embedding, distance: 'cosine').limit(ai_agent.context_limit).to_a
  end

  # The customer messages since the last reply, so a burst of short messages is searched as one question.
  def latest_customer_text
    messages.reverse.take_while { |message| message[:role] == :user }.reverse.pluck(:content).join("\n").last(MAX_QUERY_CHARACTERS)
  end

  def llm_messages
    messages.map do |message|
      attachments = message[:attachments].presence
      { role: message[:role], content: attachments ? RubyLLM::Content.new(message[:content], attachments) : message[:content] }
    end
  end

  def client
    @client ||= AiAgents::LlmClient.new
  end
end

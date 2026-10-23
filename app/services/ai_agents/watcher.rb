# The Watcher setting: a second, lighter look at the conversation after an AI reply, so a handoff or label the
# reply missed is still applied. The transcript goes in as one message, since the latest turn is the agent's.
class AiAgents::Watcher
  INSTRUCTIONS = <<~TEXT.freeze
    You review a conversation between a customer and an AI agent, ending with the agent's latest reply.
    Decide which of the actions below apply to the conversation now.
  TEXT

  pattr_initialize [:ai_agent!, :messages!, :written_rows]

  def perform
    content = AiAgents::LlmClient.new.chat(
      model: ai_agent.model, temperature: AiAgents::ReplyGenerator::TEMPERATURES['precise'],
      instructions: "#{INSTRUCTIONS}\n#{actions.instructions}", messages: [{ role: :user, content: transcript }],
      schema: actions.json_schema('ai_agent_watch')
    )
    actions.parse(content.is_a?(Hash) ? content : {})
  end

  private

  def transcript
    messages.map { |message| "#{message[:role] == :user ? 'Customer' : 'AI agent'}: #{message[:content]}" }.join("\n")
  end

  def actions
    @actions ||= AiAgents::ActionSchema.new(ai_agent: ai_agent, written_rows: written_rows)
  end
end

# Answers the latest customer message of a conversation the AI agent is handling (see ConversationSession#ai_active?).
# One job is queued per incoming message (after the agent's Message Await delay), and only the job for the
# newest message replies, so a burst of messages gets a single answer.
class AiAgents::ReplyJob < ApplicationJob
  queue_as :high

  def perform(message)
    conversation = message.conversation
    ai_agent = conversation.inbox.ai_agent
    return unless ai_agent

    session = AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
    reply(session, ai_agent, message) if answerable?(session, message)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    session&.handoff!(:error)
  end

  private

  def reply(session, ai_agent, message)
    return session.handoff!(:message_limit) if session.reply_count >= ai_agent.message_limit

    reply = AiAgents::ReplyGenerator.new(ai_agent: ai_agent, messages: session.history).perform
    # The customer may have written again while the reply was generated; that message's job answers both.
    return unless answerable?(session, message)

    reply.messages.each { |content| session.reply!(content, to: message) } unless reply.handoff && ai_agent.silent_handoff
    session.apply!(handoff: reply.handoff, labels: reply.labels, reason: :transfer_conditions)
    AiAgents::WatchJob.perform_later(message.conversation) if watch?(ai_agent, reply)
  end

  # The Watcher only has something to check when the agent has transfer conditions or allowed labels.
  def watch?(ai_agent, reply)
    ai_agent.watcher_enabled && !reply.handoff && AiAgents::ActionSchema.new(ai_agent: ai_agent).any?
  end

  def answerable?(session, message)
    message.conversation.reload
    session.ai_active? && message.conversation.messages.incoming.maximum(:id) == message.id
  end
end

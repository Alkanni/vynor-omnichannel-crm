# Answers the latest customer message of a conversation the AI agent is handling (see ConversationSession#ai_active?).
# One job is queued per incoming message (after the agent's Message Await delay), and only the job for the
# newest message replies, so a burst of messages gets a single answer. Each answered message gets an
# AiAgent::ReplyTrace.
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
    if session
      session.handoff!(:error)
      record_trace(ai_agent, message, :error, error_class: e.class.name)
    end
  end

  private

  def reply(session, ai_agent, message)
    if session.reply_count >= ai_agent.message_limit
      session.handoff!(:message_limit)
      return record_trace(ai_agent, message, :message_limit)
    end

    reply = AiAgents::ReplyGenerator.new(ai_agent: ai_agent, messages: session.history, written_rows: session.sheet_rows).perform
    # The customer may have written again while the reply was generated; that message's job answers both.
    deliver(session, ai_agent, message, reply) if answerable?(session, message)
  end

  def deliver(session, ai_agent, message, reply)
    reply.messages.each { |content| session.reply!(content, to: message) } unless reply.handoff && ai_agent.silent_handoff
    session.apply!(handoff: reply.handoff, labels: reply.labels, sheet_row: reply.sheet_row, reason: :transfer_conditions)
    AiAgents::WatchJob.perform_later(message.conversation) if watch?(ai_agent, reply)
    record_trace(ai_agent, message, reply.handoff ? :handoff : :replied, labels: reply.labels, **reply.trace.attributes)
  end

  def record_trace(ai_agent, message, status, details = {})
    ai_agent.reply_traces.create!(account_id: ai_agent.account_id, conversation_id: message.conversation_id, message: message,
                                  model: ai_agent.model, status: status, **details)
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

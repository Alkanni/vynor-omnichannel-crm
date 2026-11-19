# Answers the latest customer message of a conversation the AI agent is handling (see ConversationSession#ai_active?).
# One job is queued per incoming message (after the agent's Message Await delay), and only the job for the
# newest message replies, so a burst of messages gets a single answer. Each answered message gets an
# AiAgent::ReplyTrace, and each reply the request log of its run (see AiAgents::RequestRecorder).
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

    history = session.history
    AiAgents::RequestRecorder.record(ai_agent: ai_agent, source: :reply, input: { messages: history }, conversation_id: message.conversation_id,
                                     message_id: message.id) do |log|
      reply = AiAgents::ReplyGenerator.new(ai_agent: ai_agent, messages: history, written_rows: session.sheet_rows,
                                           bookings: session.bookings).perform
      # The customer may have written again while the reply was generated; that message's job answers both.
      deliver(session, ai_agent, message, reply, log) if answerable?(session, message)
    end
  end

  def deliver(session, ai_agent, message, reply, log)
    sent = reply.handoff && ai_agent.silent_handoff ? [] : reply.messages
    sent.each { |content| session.reply!(content, to: message) }
    session.apply!(handoff: reply.handoff, labels: reply.labels, sheet_row: reply.sheet_row, booking: reply.booking, reason: :transfer_conditions)
    trace = record_trace(ai_agent, message, reply.handoff ? :handoff : :replied, labels: reply.labels, **reply.trace.attributes)
    log.output = { messages: sent, handoff: reply.handoff, labels: reply.labels, sheet_row: reply.sheet_row, booking: reply.booking }
    log.reply_trace_id = trace.id
    AiAgents::WatchJob.perform_later(message.conversation, trace) if watch?(ai_agent, reply)
  end

  def record_trace(ai_agent, message, status, details = {})
    ai_agent.reply_traces.create!(account_id: ai_agent.account_id, conversation_id: message.conversation_id, message: message,
                                  model: ai_agent.model, scope_policy_version: ai_agent.scope_policy_version, status: status, **details)
  end

  # The Watcher only has something to check when the agent has transfer conditions, allowed labels, a sheet, or bookings. A scope reply is
  # left alone, so a refused message reaches the actions no more than it reaches the reply model.
  def watch?(ai_agent, reply)
    ai_agent.watcher_enabled && !reply.handoff && !reply.scope_reply? && AiAgents::ActionSchema.new(ai_agent: ai_agent).any?
  end

  def answerable?(session, message)
    message.conversation.reload
    session.ai_active? && message.conversation.messages.incoming.maximum(:id) == message.id
  end
end

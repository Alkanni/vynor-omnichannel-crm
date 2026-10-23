# Answers the latest customer message of a pending conversation in an inbox connected to an AI Agent.
# One job is queued per incoming message (after the agent's Message Await delay), and only the job for the
# newest message replies, so a burst of messages gets a single answer.
class AiAgents::ReplyJob < ApplicationJob
  queue_as :high

  def perform(message)
    conversation = message.conversation
    ai_agent = conversation.inbox.ai_agent
    return unless ai_agent && answerable?(conversation, message)

    reply(conversation, ai_agent, message)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    conversation.bot_handoff! if conversation.reload.pending?
  end

  private

  def reply(conversation, ai_agent, message)
    session = AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
    return conversation.bot_handoff! if session.reply_count >= ai_agent.message_limit

    replies = AiAgents::ReplyGenerator.new(ai_agent: ai_agent, messages: session.history).perform
    # The customer may have written again while the reply was generated; that message's job answers both.
    return unless answerable?(conversation.reload, message)

    replies.each { |content| session.reply!(content, to: message) }
  end

  def answerable?(conversation, message)
    conversation.pending? && conversation.messages.incoming.maximum(:id) == message.id
  end
end

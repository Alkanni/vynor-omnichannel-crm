# Runs the Watcher after an AI reply; see AiAgents::Watcher.
class AiAgents::WatchJob < ApplicationJob
  queue_as :high

  def perform(conversation)
    ai_agent = conversation.inbox.ai_agent
    return unless ai_agent

    session = AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
    # A human agent may have taken over since the reply.
    return unless session.ai_active?

    actions = AiAgents::Watcher.new(ai_agent: ai_agent, messages: session.history).perform
    session.apply!(**actions, reason: :watcher)
  rescue StandardError => e
    # The reply was already sent, so a failed check is reported without handing the conversation off.
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  end
end

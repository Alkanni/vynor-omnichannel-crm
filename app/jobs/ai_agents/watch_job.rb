# Runs the Watcher after an AI reply (see AiAgents::Watcher) and adds its tokens to the trace of that reply.
class AiAgents::WatchJob < ApplicationJob
  queue_as :high

  def perform(conversation, reply_trace)
    ai_agent = conversation.inbox.ai_agent
    return unless ai_agent

    session = AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
    # A human agent may have taken over since the reply.
    return unless session.ai_active?

    result = AiAgents::Watcher.new(ai_agent: ai_agent, messages: session.history, written_rows: session.sheet_rows).perform
    session.apply!(**result.actions, reason: :watcher)
    reply_trace.update!(watcher_input_tokens: result.input_tokens, watcher_output_tokens: result.output_tokens,
                        watcher_cached_input_tokens: result.cached_input_tokens)
  rescue StandardError => e
    # The reply was already sent, so a failed check is reported without handing the conversation off.
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  end
end

# Runs the Watcher after an AI reply (see AiAgents::Watcher) and adds its tokens to the trace of that reply. Its request log
# is linked to that trace (see AiAgents::RequestRecorder).
class AiAgents::WatchJob < ApplicationJob
  queue_as :high

  def perform(conversation, reply_trace)
    ai_agent = conversation.inbox.ai_agent
    return unless ai_agent

    session = AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
    # A human agent may have taken over since the reply.
    return unless session.ai_active?

    history = session.history
    AiAgents::RequestRecorder.record(ai_agent: ai_agent, source: :watcher, input: { messages: history }, conversation_id: conversation.id,
                                     message_id: reply_trace.message_id, reply_trace_id: reply_trace.id) do |log|
      result = AiAgents::Watcher.new(ai_agent: ai_agent, messages: history, written_rows: session.sheet_rows, bookings: session.bookings).perform
      log.output = result.actions
      session.apply!(**result.actions, reason: :watcher)
      reply_trace.update!(watcher_input_tokens: result.input_tokens, watcher_output_tokens: result.output_tokens,
                          watcher_cached_input_tokens: result.cached_input_tokens)
    end
  rescue StandardError => e
    # The reply was already sent, so a failed check is reported without handing the conversation off.
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  end
end

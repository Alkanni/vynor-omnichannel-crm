# Writes a row an AI reply decided on to the agent's Google Sheet. Losing access to the sheet (or the grant) marks the
# integration needs_reconnect, which stops further writes; transient Google errors are left to the job retry.
class AiAgents::AppendSheetRowJob < ApplicationJob
  queue_as :default

  RECONNECT_STATUSES = [nil, 400, 401, 403, 404].freeze

  def perform(conversation, values)
    ai_agent = conversation.inbox.ai_agent
    integration = ai_agent&.google_sheets_integration
    return unless integration&.connected?

    session = AiAgents::ConversationSession.new(conversation: conversation, ai_agent: ai_agent)
    return if session.sheet_rows.include?(values)

    AiAgents::GoogleSheetsClient.new(integration).append_row(values)
    session.record_sheet_row!(values)
  rescue AiAgents::GoogleSheetsError => e
    raise unless RECONNECT_STATUSES.include?(e.status)

    integration.needs_reconnect!
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  end
end

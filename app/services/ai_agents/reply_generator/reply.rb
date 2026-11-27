# The reply of AiAgents::ReplyGenerator: the bubbles to send, the actions to apply, and how it was made (trace).
# booking_missing_fields names the required fields a booking it asked for left empty (see AiAgents::ActionSchema), else
# nil. booking_summary is the summary bubble the reply ends with, else nil, and booking_summary_rejection why the booking
# it asked to show cannot be one (see AiAgents::BookingSummary).
AiAgents::ReplyGenerator::Reply = Data.define(
  :messages, :handoff, :labels, :sheet_row, :booking, :booking_rejection, :booking_missing_fields, :booking_cancellation, :booking_summary,
  :booking_summary_rejection, :trace
) do
  # rubocop:disable Metrics/ParameterLists
  def initialize(messages:, handoff:, labels:, trace:, sheet_row: nil, booking: nil, booking_rejection: nil, booking_missing_fields: nil,
                 booking_cancellation: nil, booking_summary: nil, booking_summary_rejection: nil)
    super
  end
  # rubocop:enable Metrics/ParameterLists

  # What AiAgents::ConversationSession#apply! takes besides the reason.
  def actions = to_h.slice(:handoff, :labels, :sheet_row, :booking, :booking_rejection, :booking_missing_fields, :booking_cancellation)

  # The promotion the reply mentions once sent (see AiAgents::KnowledgeRetriever::Result#mentioned_promotion_id), else nil,
  # as for a scope reply.
  def promotion_id = trace.retrieval&.mentioned_promotion_id(trace.validation)

  # Sent for a decision of the scope check, so it involved neither the knowledge nor the reply model.
  def scope_reply? = trace.scope&.reply_attribute.present?
end

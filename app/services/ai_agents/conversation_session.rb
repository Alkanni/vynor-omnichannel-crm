# A session runs from the last time the conversation was resolved, which is when the AI Message Limit resets
# and where Session-Only Memory starts. Handoffs and pending messages are tracked per session as well.
class AiAgents::ConversationSession
  REPLY_MARKER = 'ai_agent_reply_to'.freeze
  HANDOFF_MARKER = 'ai_agent_handoff'.freeze
  PENDING_MARKER = 'ai_agent_pending'.freeze
  SHEET_ROW_MARKER = 'ai_agent_sheet_row'.freeze
  WELCOME_MARKER = 'ai_agent_welcome'.freeze
  BOOKING_REJECTED_MARKER = 'ai_agent_booking_rejected'.freeze
  BOOKING_CANCELLATION_MARKER = 'ai_agent_booking_cancellation'.freeze

  pattr_initialize [:conversation!, :ai_agent!]

  # The conversation's AI agent and whether it answers the conversation now, for the dashboard (meta.ai_agent of the
  # conversation payload); nil when the inbox has no AI agent.
  def self.event_data(conversation)
    ai_agent = conversation.inbox.ai_agent
    return unless ai_agent

    { id: ai_agent.id, name: ai_agent.name, active: new(conversation: conversation, ai_agent: ai_agent).ai_active? }
  end

  # Pending conversations belong to the AI. After a handoff it keeps answering only when Stop AI after Handoff
  # and Silent Agent Handoff are both off, and only until a human agent replies.
  def ai_active?
    return true if conversation.pending?
    return false if ai_agent.stop_ai_after_handoff || ai_agent.silent_handoff

    awaiting_human?
  end

  # The AI replies counted toward the Message Limit. While the conversation is pending only those since it became
  # pending count, so a conversation a human hands back to the AI gets a fresh limit.
  def reply_count
    replies = session_messages.where(sender: ai_agent)
    replies = replies.where('messages.created_at > ?', conversation.status_changed_at) if conversation.pending? && conversation.status_changed_at
    replies.distinct.count(Arel.sql("messages.additional_attributes ->> '#{REPLY_MARKER}'"))
  end

  def history
    records = history_records
    with_files = records.last(ai_agent.read_file_limit)

    records.filter_map do |message|
      content = message.content_for_llm
      next if content.blank?

      { role: message.incoming? ? :user : :assistant, content: content, attachments: with_files.include?(message) ? images(message) : [] }
    end
  end

  def reply!(content, to:)
    send_message(content, REPLY_MARKER => to.id)
  end

  # booking: the attributes of a Booking the reply asked for, booking_rejection: why one it asked for cannot be a
  # booking, and booking_cancellation: the id of a booking the customer asked to cancel (see AiAgents::ActionSchema#parse).
  # rubocop:disable Metrics/ParameterLists
  def apply!(handoff:, labels:, reason:, sheet_row: nil, booking: nil, booking_rejection: nil, booking_cancellation: nil)
    add_labels(labels)
    AiAgents::AppendSheetRowJob.perform_later(conversation, sheet_row) if sheet_row
    request_booking!(booking) if booking
    reject_booking!(booking_rejection) if booking_rejection
    request_cancellation!(booking_cancellation) if booking_cancellation
    handoff!(reason) if handoff
  end
  # rubocop:enable Metrics/ParameterLists

  # The bookings the customer still has in this conversation.
  def bookings
    conversation.bookings.where(status: %i[requested confirmed]).order(:scheduled_at)
  end

  # Rows the AI wrote to Google Sheets for this conversation, from the activity messages that record them.
  def sheet_rows
    conversation.messages.activity.where("messages.additional_attributes ->> '#{SHEET_ROW_MARKER}' IS NOT NULL")
                .reorder(:id).map { |message| message.additional_attributes[SHEET_ROW_MARKER] }
  end

  def record_sheet_row!(values)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
      content: I18n.t('ai_agents.google_sheets.row_added', agent: ai_agent.name), additional_attributes: { SHEET_ROW_MARKER => values }
    )
  end

  # The only way the AI hands a conversation over to humans. The activity message tells agents why and marks
  # when it happened, which the rules after a handoff rely on.
  def handoff!(reason)
    return unless conversation.reload.pending?

    conversation.team = nil if ai_agent.ignore_team_handoff
    conversation.bot_handoff!
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
      content: I18n.t('ai_agents.handoff.activity', agent: ai_agent.name, reason: I18n.t("ai_agents.handoff.reasons.#{reason}")),
      additional_attributes: { HANDOFF_MARKER => reason }
    )
  end

  # While the customer waits for a human after a handoff, tells them once per handoff whether an agent is assigned.
  def send_pending_message
    return unless ai_agent.stop_ai_after_handoff && !ai_agent.silent_handoff && awaiting_human?

    kind = conversation.assignee_id.present? ? 'assigned' : 'unassigned'
    content = ai_agent.public_send("pending_#{kind}_message")
    return if content.blank?
    return if messages_since_handoff.where(sender: ai_agent).exists?(["messages.additional_attributes ->> '#{PENDING_MARKER}' = ?", kind])

    send_message(content, PENDING_MARKER => kind)
  end

  private

  # The latest messages up to the history limit, oldest first. Channels that create the conversation with the first
  # customer message get the welcome message after it, and a history ending with the welcome would hide the
  # customer's question, so the welcome goes first.
  def history_records
    scope = ai_agent.session_only_memory ? session_messages : conversation.messages
    records = scope.where(message_type: [:incoming, :outgoing], private: false).reorder(id: :desc).limit(ai_agent.history_limit).to_a.reverse
    records.partition { |message| message.additional_attributes.key?(WELCOME_MARKER) }.flatten
  end

  def awaiting_human?
    conversation.open? && last_handoff.present? &&
      !messages_since_handoff.exists?(message_type: :outgoing, private: false, sender_type: 'User')
  end

  def last_handoff
    session_messages.activity.where("messages.additional_attributes ->> '#{HANDOFF_MARKER}' IS NOT NULL").reorder(:id).last
  end

  def messages_since_handoff
    conversation.messages.where('messages.id > ?', last_handoff.id)
  end

  def session_messages
    started_at = ReportingEvent.where(conversation_id: conversation.id, name: 'conversation_resolved').maximum(:event_end_time)
    started_at ? conversation.messages.where('messages.created_at > ?', started_at) : conversation.messages
  end

  # After a handoff the customer still waits for a human agent, so AI messages there leave waiting_since alone.
  def send_message(content, marker)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
      sender: ai_agent, content: content, additional_attributes: marker, preserve_waiting_since: conversation.open?
    )
  end

  # A booking with the same service and time as one the customer still has is not requested again. The reply and the
  # Watcher may both ask for it, so the check and the insert run under the conversation's row lock, taken on a copy of
  # the row so the record in hand is left as it is. A booking that replaces one the customer still has marks that one
  # rescheduled, without a message to the customer; one the staff changed meanwhile is not replaced.
  def request_booking!(attributes)
    customer_name = booking_customer_name(attributes)
    return reject_booking!(:missing_customer_name) unless customer_name

    booking = Conversation.transaction do
      Conversation.lock.find(conversation.id)
      next if holds_booking?(attributes)

      replaced = reschedule!(attributes[:rescheduled_from_id])
      conversation.bookings.create!(account: conversation.account, contact: conversation.contact, ai_agent: ai_agent,
                                    **attributes, customer_name: customer_name, rescheduled_from_id: replaced&.id)
    end
    announce_booking!(booking) if booking
  end

  def holds_booking?(attributes)
    bookings.any? { |held| held.scheduled_at == attributes[:scheduled_at] && held.service.casecmp?(attributes[:service]) }
  end

  # Marks the booking a new one replaces as rescheduled, when the customer still has it, and returns it.
  def reschedule!(id)
    bookings.find_by(id: id)&.tap(&:rescheduled!) if id
  end

  # The name the model gave, else the contact's (the model often leaves it blank when the customer never said it).
  def booking_customer_name(attributes)
    attributes[:customer_name].presence || conversation.contact.name.to_s.strip.presence
  end

  # The agent's booking label and an activity message tell the staff, who confirm the booking.
  def announce_booking!(booking)
    add_booking_label
    key = booking.rescheduled_from_id ? 'rescheduled' : 'requested'
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
      content: I18n.t("ai_agents.bookings.#{key}", agent: ai_agent.name, id: booking.id, service: booking.service,
                                                   scheduled_at: local_time(booking), previous: booking.rescheduled_from_id)
    )
  end

  # A cancellation the customer asked for leaves the booking as it is and tells the staff, who cancel it, once per
  # customer message, as for a rejected booking.
  def request_cancellation!(id)
    booking = bookings.find_by(id: id)
    return if booking.nil? || noted_since_customer_wrote?(BOOKING_CANCELLATION_MARKER)

    add_booking_label
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
      content: I18n.t('ai_agents.bookings.cancellation_requested', agent: ai_agent.name, id: booking.id, service: booking.service,
                                                                   scheduled_at: local_time(booking)),
      additional_attributes: { BOOKING_CANCELLATION_MARKER => booking.id }
    )
  end

  # A booking the model asked for that cannot be recorded tells the staff why, with the agent's booking label, so they
  # follow it up with the customer, who was told the staff will confirm it. The reply and the Watcher may both ask for
  # it after the same customer message, which tells the staff once.
  def reject_booking!(reason)
    return if noted_since_customer_wrote?(BOOKING_REJECTED_MARKER)

    add_booking_label
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
      content: I18n.t('ai_agents.bookings.rejected', agent: ai_agent.name, reason: I18n.t("ai_agents.bookings.rejection_reasons.#{reason}")),
      additional_attributes: { BOOKING_REJECTED_MARKER => reason }
    )
  end

  def noted_since_customer_wrote?(marker)
    conversation.messages.activity.where("messages.additional_attributes ->> '#{marker}' IS NOT NULL")
                .exists?(['messages.id > ?', conversation.messages.incoming.maximum(:id)])
  end

  def local_time(booking)
    booking.scheduled_at.in_time_zone(ai_agent.timezone).strftime('%Y-%m-%d %H:%M %Z')
  end

  def add_booking_label
    add_labels(conversation.account.labels.where(id: ai_agent.booking_label_id).pluck(:title))
  end

  # Label activity messages name the AI agent rather than nobody.
  def add_labels(labels)
    return if labels.empty?

    Current.executed_by = ai_agent
    conversation.add_labels(labels)
  ensure
    Current.executed_by = nil
  end

  def images(message)
    message.attachments.select { |attachment| attachment.image? && attachment.file.attached? }.map { |attachment| attachment.file.blob }
  end
end

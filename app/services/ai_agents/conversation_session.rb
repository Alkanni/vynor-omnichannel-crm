# A session runs from the last time the conversation was resolved, which is when the AI Message Limit resets
# and where Session-Only Memory starts. Handoffs and pending messages are tracked per session as well.
class AiAgents::ConversationSession
  REPLY_MARKER = 'ai_agent_reply_to'.freeze
  HANDOFF_MARKER = 'ai_agent_handoff'.freeze
  PENDING_MARKER = 'ai_agent_pending'.freeze
  SHEET_ROW_MARKER = 'ai_agent_sheet_row'.freeze
  WELCOME_MARKER = 'ai_agent_welcome'.freeze

  pattr_initialize [:conversation!, :ai_agent!]

  # Pending conversations belong to the AI. After a handoff it keeps answering only when Stop AI after Handoff
  # and Silent Agent Handoff are both off, and only until a human agent replies.
  def ai_active?
    return true if conversation.pending?
    return false if ai_agent.stop_ai_after_handoff || ai_agent.silent_handoff

    awaiting_human?
  end

  def reply_count
    session_messages.where(sender: ai_agent).distinct.count(Arel.sql("messages.additional_attributes ->> '#{REPLY_MARKER}'"))
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

  # booking: the attributes of a Booking the reply asked for (see AiAgents::ActionSchema#parse).
  def apply!(handoff:, labels:, reason:, sheet_row: nil, booking: nil)
    add_labels(labels)
    AiAgents::AppendSheetRowJob.perform_later(conversation, sheet_row) if sheet_row
    request_booking!(booking) if booking
    handoff!(reason) if handoff
  end

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
  # the row so the record in hand is left as it is.
  def request_booking!(attributes)
    booking = Conversation.transaction do
      Conversation.lock.find(conversation.id)
      next if bookings.any? { |held| held.scheduled_at == attributes[:scheduled_at] && held.service.casecmp?(attributes[:service]) }

      conversation.bookings.create!(account: conversation.account, contact: conversation.contact, ai_agent: ai_agent, **attributes)
    end
    announce_booking!(booking) if booking
  end

  # The agent's booking label and an activity message tell the staff, who confirm the booking.
  def announce_booking!(booking)
    add_labels(conversation.account.labels.where(id: ai_agent.booking_label_id).pluck(:title))
    scheduled_at = booking.scheduled_at.in_time_zone(ai_agent.timezone).strftime('%Y-%m-%d %H:%M %Z')
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
      content: I18n.t('ai_agents.bookings.requested', agent: ai_agent.name, id: booking.id, service: booking.service, scheduled_at: scheduled_at)
    )
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

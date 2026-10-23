# A session runs from the last time the conversation was resolved, which is when the AI Message Limit resets
# and where Session-Only Memory starts. Handoffs and pending messages are tracked per session as well.
class AiAgents::ConversationSession
  REPLY_MARKER = 'ai_agent_reply_to'.freeze
  HANDOFF_MARKER = 'ai_agent_handoff'.freeze
  PENDING_MARKER = 'ai_agent_pending'.freeze

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
    scope = ai_agent.session_only_memory ? session_messages : conversation.messages
    records = scope.where(message_type: [:incoming, :outgoing], private: false).reorder(id: :desc).limit(ai_agent.history_limit).to_a.reverse
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

  def apply!(handoff:, labels:, reason:)
    add_labels(labels)
    handoff!(reason) if handoff
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

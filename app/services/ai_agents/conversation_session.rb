# A session runs from the last time the conversation was resolved, which is when the AI Message Limit resets
# and where Session-Only Memory starts.
class AiAgents::ConversationSession
  REPLY_MARKER = 'ai_agent_reply_to'.freeze

  pattr_initialize [:conversation!, :ai_agent!]

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
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
      sender: ai_agent, content: content, additional_attributes: { REPLY_MARKER => to.id }
    )
  end

  private

  def session_messages
    started_at = ReportingEvent.where(conversation_id: conversation.id, name: 'conversation_resolved').maximum(:event_end_time)
    started_at ? conversation.messages.where('messages.created_at > ?', started_at) : conversation.messages
  end

  def images(message)
    message.attachments.select { |attachment| attachment.image? && attachment.file.attached? }.map { |attachment| attachment.file.blob }
  end
end

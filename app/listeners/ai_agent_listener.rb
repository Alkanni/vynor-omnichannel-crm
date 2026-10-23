class AiAgentListener < BaseListener
  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    ai_agent = conversation.inbox.ai_agent
    return unless ai_agent&.welcome_message.present? && conversation.pending?

    conversation.messages.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
                                  sender: ai_agent, content: ai_agent.welcome_message)
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    ai_agent = message.inbox.ai_agent
    return unless ai_agent && message.incoming? && message.conversation.pending?

    AiAgents::ReplyJob.set(wait: ai_agent.message_await.seconds).perform_later(message)
  end
end

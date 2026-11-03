# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_reply_trace, class: 'AiAgent::ReplyTrace' do
    ai_agent
    account { ai_agent.account }
    conversation { association :conversation, account: account }
    message { association :message, account: account, conversation: conversation }
    model { ai_agent.model }
    status { :replied }
  end
end

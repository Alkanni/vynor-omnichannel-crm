# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_inbox do
    ai_agent
    inbox { association :inbox, account: ai_agent.account }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_promotion, class: 'AiAgent::Promotion' do
    ai_agent
    sequence(:title) { |n| "Promotion #{n}" }
    description { 'Tune Up Throttle Body Rp80.000, dari Rp100.000' }
  end
end

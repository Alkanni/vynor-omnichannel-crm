# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_product, class: 'AiAgent::Product' do
    ai_agent
    sequence(:name) { |n| "Product #{n}" }
    description { 'Tune up throttle body' }
    price { 285_000 }
    weight { 1 }
    stock { 100 }
  end
end

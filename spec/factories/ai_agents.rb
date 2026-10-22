# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent do
    account
    sequence(:name) { |n| "AI Agent #{n}" }
    behavior { 'You are a helpful customer service agent.' }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_knowledge_source, class: 'AiAgent::KnowledgeSource' do
    ai_agent
    source_type { :text }
    sequence(:title) { |n| "Knowledge #{n}" }
    content { 'Grand Sehat buka setiap hari pukul 07.30 - 18.00.' }

    trait :qa do
      source_type { :qa }
      title { 'Berapa lama proses detailing?' }
      content { 'Eksterior 4-5 jam, interior 3-4 jam.' }
    end
  end
end

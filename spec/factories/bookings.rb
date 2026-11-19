# frozen_string_literal: true

FactoryBot.define do
  factory :booking do
    account
    conversation { association :conversation, account: account }
    contact { conversation.contact }
    service { 'Cuci salon' }
    customer_name { 'Budi' }
    scheduled_at { 1.day.from_now }
  end
end

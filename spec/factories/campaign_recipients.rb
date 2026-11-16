# frozen_string_literal: true

FactoryBot.define do
  factory :campaign_recipient do
    campaign
    account { campaign.account }
    inbox { campaign.inbox }
    contact { association :contact, account: campaign.account }
  end
end

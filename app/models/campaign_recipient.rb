# == Schema Information
#
# Table name: campaign_recipients
#
#  id              :bigint           not null, primary key
#  delivered_at    :datetime
#  error_code      :string
#  error_message   :text
#  error_title     :string
#  failed_at       :datetime
#  message_content :text
#  read_at         :datetime
#  sent_at         :datetime
#  status          :integer          default("queued"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  campaign_id     :bigint           not null
#  contact_id      :bigint           not null
#  inbox_id        :bigint           not null
#  source_id       :string
#
# Indexes
#
#  index_campaign_recipients_on_account_id                  (account_id)
#  index_campaign_recipients_on_account_id_and_campaign_id  (account_id,campaign_id)
#  index_campaign_recipients_on_campaign_id                 (campaign_id)
#  index_campaign_recipients_on_campaign_id_and_contact_id  (campaign_id,contact_id) UNIQUE
#  index_campaign_recipients_on_campaign_id_and_status      (campaign_id,status)
#  index_campaign_recipients_on_contact_id                  (contact_id)
#  index_campaign_recipients_on_inbox_id                    (inbox_id)
#  index_campaign_recipients_on_source_id                   (source_id) UNIQUE WHERE (source_id IS NOT NULL)
#
# One row per contact in a one-off campaign audience, following the delivery of the campaign message sent to it.
class CampaignRecipient < ApplicationRecord
  # Delivery only moves forward: a late `delivered` webhook never overrides `read`, and a message that already
  # reached the contact is not marked failed afterwards.
  DELIVERY_PROGRESS = %w[queued sent delivered read].freeze
  EXTERNAL_ERROR_FORMAT = /\A(?<code>\d+): (?<title>.+)\z/

  belongs_to :account
  belongs_to :campaign
  belongs_to :contact
  belongs_to :inbox

  enum :status, { queued: 0, skipped: 1, sent: 2, delivered: 3, read: 4, failed: 5 }

  validates :contact_id, uniqueness: { scope: :campaign_id }

  def mark_skipped!(reason)
    update!(status: :skipped, error_message: reason)
  end

  def sync_with_message!(message)
    with_lock do
      new_status = delivery_status(message)
      next unless advances_to?(new_status)

      update!(status: new_status, source_id: message.source_id, "#{new_status}_at": Time.current, **error_attributes(message))
    end
  end

  private

  def delivery_status(message)
    return 'failed' if message.failed?
    return message.status if message.delivered? || message.read?

    'sent' if message.source_id.present?
  end

  def advances_to?(new_status)
    return false if new_status.blank? || DELIVERY_PROGRESS.exclude?(status)
    return %w[queued sent].include?(status) if new_status == 'failed'

    DELIVERY_PROGRESS.index(new_status) > DELIVERY_PROGRESS.index(status)
  end

  # Status webhooks store the error as "<code>: <title>", while a rejected API call stores Meta's message as is.
  def error_attributes(message)
    return {} unless message.failed?

    match = message.external_error.to_s.match(EXTERNAL_ERROR_FORMAT)
    return { error_message: message.external_error } unless match

    { error_code: match[:code], error_title: match[:title] }
  end
end

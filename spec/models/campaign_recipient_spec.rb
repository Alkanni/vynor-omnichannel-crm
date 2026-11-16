require 'rails_helper'

RSpec.describe CampaignRecipient do
  describe '#sync_with_message!' do
    let(:recipient) { create(:campaign_recipient) }
    let(:conversation) { create(:conversation, account: recipient.account, inbox: recipient.inbox, contact: recipient.contact) }
    let(:message) do
      create(:message, conversation: conversation, account: recipient.account, inbox: recipient.inbox, message_type: :outgoing,
                       additional_attributes: { 'campaign_id' => recipient.campaign_id })
    end

    it 'stays queued until WhatsApp accepts the message' do
      recipient.sync_with_message!(message)

      expect(recipient.reload).to be_queued
    end

    it 'is sent once WhatsApp returns a message id' do
      message.update!(source_id: 'wamid.sent')

      freeze_time do
        recipient.sync_with_message!(message)

        expect(recipient.reload).to have_attributes(status: 'sent', source_id: 'wamid.sent', sent_at: Time.current)
      end
    end

    it 'follows delivered and read webhooks' do
      message.update!(source_id: 'wamid.read', status: :delivered)
      recipient.sync_with_message!(message)
      expect(recipient.reload).to be_delivered

      message.update!(status: :read)
      recipient.sync_with_message!(message)
      expect(recipient.reload).to have_attributes(status: 'read', read_at: be_present)
    end

    it 'does not move back from read when a late delivered webhook arrives' do
      recipient.update!(status: :read)
      message.update!(source_id: 'wamid.late', status: :delivered)

      recipient.sync_with_message!(message)

      expect(recipient.reload).to be_read
    end

    it 'splits the code and title of a failed status webhook' do
      message.update!(source_id: 'wamid.failed', status: :failed, external_error: '131026: Message undeliverable')

      recipient.sync_with_message!(message)

      expect(recipient.reload).to have_attributes(status: 'failed', error_code: '131026', error_title: 'Message undeliverable',
                                                  error_message: nil, failed_at: be_present)
    end

    it 'keeps the error of a rejected API call as the message' do
      message.update!(status: :failed, external_error: '(#132001) Template name does not exist in the translation')

      recipient.sync_with_message!(message)

      expect(recipient.reload).to have_attributes(status: 'failed', error_message: '(#132001) Template name does not exist in the translation')
    end

    it 'does not mark a delivered message as failed' do
      recipient.update!(status: :delivered)
      message.update!(source_id: 'wamid.delivered', status: :failed, external_error: '131000: Something went wrong')

      recipient.sync_with_message!(message)

      expect(recipient.reload).to be_delivered
    end

    it 'leaves skipped recipients alone' do
      recipient.mark_skipped!('Phone number and BSUID are missing')
      message.update!(source_id: 'wamid.skipped')

      recipient.sync_with_message!(message)

      expect(recipient.reload).to have_attributes(status: 'skipped', error_message: 'Phone number and BSUID are missing')
    end
  end
end

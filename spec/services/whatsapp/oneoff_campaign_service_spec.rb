require 'rails_helper'

describe Whatsapp::OneoffCampaignService do
  let(:account) { create(:account).tap { |new_account| new_account.enable_features!(:whatsapp_campaign) } }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let!(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:label1) { create(:label, account: account) }
  let(:label2) { create(:label, account: account) }
  let!(:campaign) do
    create(:campaign, inbox: whatsapp_inbox, account: account, message: 'Hi {{contact.name}}, your ticket is updated',
                      audience: [{ type: 'Label', id: label1.id }, { type: 'Label', id: label2.id }],
                      template_params: template_params)
  end
  let(:template_params) do
    {
      'name' => 'ticket_status_updated',
      'namespace' => '23423423_2342423_324234234_2343224',
      'category' => 'UTILITY',
      'language' => 'en',
      'processed_params' => { 'body' => { 'name' => '{{contact.name}}', 'ticket_id' => '2332' } }
    }
  end

  describe '#perform' do
    context 'when campaign validation fails' do
      it 'raises error if campaign is completed' do
        campaign.completed!

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'Completed Campaign'
      end

      it 'raises error when campaign is not a WhatsApp campaign' do
        sms_channel = create(:channel_sms, account: account)
        sms_inbox = create(:inbox, channel: sms_channel, account: account)
        invalid_campaign = create(:campaign, inbox: sms_inbox, account: account)

        expect { described_class.new(campaign: invalid_campaign).perform }
          .to raise_error "Invalid campaign #{invalid_campaign.id}"
      end

      it 'raises error when campaign is not oneoff' do
        allow(campaign).to receive(:one_off?).and_return(false)

        expect { described_class.new(campaign: campaign).perform }.to raise_error "Invalid campaign #{campaign.id}"
      end

      it 'raises error when channel provider is not whatsapp_cloud' do
        whatsapp_channel.update!(provider: 'default')

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'WhatsApp Cloud provider required'
      end

      it 'raises error when WhatsApp campaigns feature is not enabled' do
        account.disable_features!(:whatsapp_campaign)

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'WhatsApp campaigns feature not enabled'
      end
    end

    context 'when campaign is valid' do
      let(:contact) { create(:contact, :with_phone_number, account: account, name: 'Jane Smith') }

      before { contact.update_labels([label1.title]) }

      it 'marks campaign as completed' do
        described_class.new(campaign: campaign).perform

        expect(campaign.reload.completed?).to be true
      end

      it 'tracks every contact with a matching label as a queued recipient' do
        contact_with_label2, contact_with_both_labels = create_list(:contact, 2, :with_phone_number, account: account)
        contact_with_label2.update_labels([label2.title])
        contact_with_both_labels.update_labels([label1.title, label2.title])

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.pluck(:contact_id, :status, :inbox_id, :account_id)).to contain_exactly(
          [contact.id, 'queued', whatsapp_inbox.id, account.id],
          [contact_with_label2.id, 'queued', whatsapp_inbox.id, account.id],
          [contact_with_both_labels.id, 'queued', whatsapp_inbox.id, account.id]
        )
      end

      it 'queues the template as an outgoing message in the conversation of the contact phone number' do
        expect { described_class.new(campaign: campaign).perform }.to have_enqueued_job(SendReplyJob)

        message = Message.find_by!("additional_attributes->>'campaign_id' = ?", campaign.id.to_s)
        expect(message).to have_attributes(message_type: 'outgoing', private: false, content: 'Hi Jane Smith, your ticket is updated')
        expect(message.additional_attributes['template_params']).to eq(
          template_params.merge('processed_params' => { 'body' => { 'name' => 'Jane Smith', 'ticket_id' => '2332' } })
        )
        expect(message.conversation).to have_attributes(contact_id: contact.id, campaign_id: campaign.id)
        expect(message.conversation.contact_inbox.source_id).to eq(contact.phone_number.delete('+'))
        recipient = campaign.campaign_recipients.sole
        expect(recipient.message_content).to eq('Hi Jane Smith, your ticket is updated')
        expect(message.additional_attributes['campaign_recipient_id']).to eq(recipient.id)
      end

      it 'adds the message to the open conversation the reply lands in' do
        contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: contact.phone_number.delete('+'))
        open_conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, contact_inbox: contact_inbox)

        expect { described_class.new(campaign: campaign).perform }.not_to change(Conversation, :count)
        expect(open_conversation.messages.outgoing.last.additional_attributes['campaign_id']).to eq(campaign.id)
      end

      it 'starts a new conversation when the last one is resolved' do
        contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: contact.phone_number.delete('+'))
        create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)

        expect { described_class.new(campaign: campaign).perform }.to change(Conversation, :count).by(1)
      end

      it 'reuses the resolved conversation when the inbox keeps a single conversation per contact' do
        whatsapp_inbox.update!(lock_to_single_conversation: true)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: contact.phone_number.delete('+'))
        resolved = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, contact_inbox: contact_inbox,
                                         status: :resolved)

        expect { described_class.new(campaign: campaign).perform }.not_to change(Conversation, :count)
        expect(resolved.messages.outgoing.count).to eq(1)
      end

      it 'starts the new conversation pending with the AI agent of the inbox' do
        ai_agent = create(:ai_agent, account: account)
        create(:ai_agent_inbox, ai_agent: ai_agent, inbox: whatsapp_inbox)

        described_class.new(campaign: campaign).perform

        expect(campaign.conversations.sole).to have_attributes(status: 'pending', ai_assignee: ai_agent)
      end

      it 'starts the new conversation open when the inbox has no bot' do
        described_class.new(campaign: campaign).perform

        expect(campaign.conversations.sole).to be_open
      end

      it 'sends to the contact BSUID when the contact has no phone number and exactly one WhatsApp identity' do
        contact.update!(phone_number: nil)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342942')

        described_class.new(campaign: campaign).perform

        expect(campaign.conversations.sole.contact_inbox).to eq(contact_inbox)
      end

      it 'skips contacts without a phone number or BSUID' do
        contact.update!(phone_number: nil)

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.sole).to have_attributes(status: 'skipped', error_message: 'Phone number and BSUID are missing')
        expect(Message.where("additional_attributes->>'campaign_id' = ?", campaign.id.to_s)).to be_empty
      end

      it 'skips a phone-less contact with multiple WhatsApp identities in the campaign inbox' do
        contact.update!(phone_number: nil)
        create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342942')
        create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342943')

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.sole).to have_attributes(
          status: 'skipped', error_message: 'Multiple WhatsApp identities found; refusing to choose a destination'
        )
      end

      it 'skips authentication templates for BSUID-only contacts' do
        contact.update!(phone_number: nil)
        create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342942')
        whatsapp_channel.update!(message_templates: [{ 'name' => 'ticket_status_updated', 'language' => 'en', 'category' => 'AUTHENTICATION' }])

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.sole).to have_attributes(
          status: 'skipped', error_message: I18n.t('errors.whatsapp.authentication_template_requires_phone')
        )
      end

      it 'skips contacts whose liquid variables resolve to blank values' do
        campaign.update!(template_params: template_params.merge('processed_params' => { 'body' => { 'email' => '{{contact.email}}' } }))
        contact.update!(email: nil)

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.sole).to have_attributes(status: 'skipped', error_message: 'Template variables resolved to blank values')
      end

      it 'keeps processing the remaining contacts after a skipped one' do
        contact_without_phone = create(:contact, account: account, phone_number: nil)
        contact_without_phone.update_labels([label1.title])

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.pluck(:contact_id, :status)).to contain_exactly(
          [contact.id, 'queued'], [contact_without_phone.id, 'skipped']
        )
        expect(campaign.reload).to be_completed
      end
    end

    context 'when template_params is missing' do
      let(:template_params) { nil }

      it 'skips the contacts' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.sole).to have_attributes(status: 'skipped', error_message: 'Template parameters are missing')
      end
    end
  end
end

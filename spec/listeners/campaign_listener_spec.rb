require 'rails_helper'
describe CampaignListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, identifier: '123') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:campaign) { create(:campaign, inbox: inbox, account: account, trigger_rules: { url: 'https://test.com' }) }

  let!(:event) do
    Events::Base.new('campaign_triggered', Time.zone.now,
                     contact_inbox: contact_inbox, event_info: { campaign_id: campaign.display_id, custom_attributes: { order_id: 321 } })
  end

  describe '#campaign_triggered' do
    let(:builder) { double }

    before do
      allow(Campaigns::CampaignConversationBuilder).to receive(:new).and_return(builder)
      allow(builder).to receive(:perform)
    end

    context 'when params contain campaign id' do
      it 'triggers campaign conversation builder' do
        expect(Campaigns::CampaignConversationBuilder).to receive(:new)
          .with({ contact_inbox_id: contact_inbox.id, campaign_display_id: campaign.display_id, conversation_additional_attributes: {},
                  custom_attributes: { order_id: 321 } }).once
        listener.campaign_triggered(event)
      end
    end

    context 'when params does not contain campaign id' do
      it 'does not trigger campaign conversation builder' do
        event = Events::Base.new('campaign_triggered', Time.zone.now,
                                 contact_inbox: contact_inbox, event_info: {})
        expect(Campaigns::CampaignConversationBuilder).to receive(:new).exactly(0).times
        listener.campaign_triggered(event)
      end
    end
  end

  describe '#message_updated' do
    let!(:recipient) { create(:campaign_recipient, campaign: campaign, contact: contact) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
    let(:message) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                       additional_attributes: { 'campaign_id' => campaign.id, 'campaign_recipient_id' => recipient.id })
    end

    it 'updates the campaign recipient of the message' do
      message.update!(source_id: 'wamid.delivered', status: :delivered)

      listener.message_updated(Events::Base.new('message.updated', Time.zone.now, message: message))

      expect(recipient.reload).to have_attributes(status: 'delivered', source_id: 'wamid.delivered')
    end

    it 'ignores a message that only names the campaign, as clients can through the messages API' do
      message.update!(additional_attributes: { 'campaign_id' => campaign.id }, source_id: 'wamid.forged')

      listener.message_updated(Events::Base.new('message.updated', Time.zone.now, message: message))

      expect(recipient.reload).to be_queued
    end

    it 'ignores a recipient of another contact' do
      other_recipient = create(:campaign_recipient, campaign: campaign)
      message.update!(additional_attributes: { 'campaign_recipient_id' => other_recipient.id }, source_id: 'wamid.other')

      listener.message_updated(Events::Base.new('message.updated', Time.zone.now, message: message))

      expect(other_recipient.reload).to be_queued
    end
  end
end

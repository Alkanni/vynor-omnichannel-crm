# Queues the campaign template as an outgoing message in each audience contact's WhatsApp conversation, so that
# agents and the AI agent see it when the contact replies, and tracks every contact as a CampaignRecipient.
# The messages go out through SendReplyJob like any other template; CampaignListener follows their delivery.
class Whatsapp::OneoffCampaignService
  class RecipientSkipped < StandardError; end

  pattr_initialize [:campaign!]

  def perform
    validate_campaign!
    process_audience(extract_audience_labels)
    campaign.completed!
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def validate_campaign_type!
    raise "Invalid campaign #{campaign.id}" unless whatsapp_campaign? && campaign.one_off?
  end

  def whatsapp_campaign?
    campaign.inbox.inbox_type == 'Whatsapp'
  end

  def validate_campaign_status!
    raise 'Completed Campaign' if campaign.completed?
  end

  def validate_provider!
    raise 'WhatsApp Cloud provider required' unless whatsapp_cloud_channel?
  end

  def validate_feature_flag!
    raise 'WhatsApp campaigns feature not enabled' unless campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def validate_campaign!
    validate_campaign_type!
    validate_campaign_status!
    validate_provider!
    validate_feature_flag!
  end

  def extract_audience_labels
    audience_label_ids = campaign.audience.select { |audience| audience['type'] == 'Label' }.pluck('id')
    campaign.account.labels.where(id: audience_label_ids).pluck(:title)
  end

  def process_audience(audience_labels)
    contacts = campaign.account.contacts.tagged_with(audience_labels, any: true)
    Rails.logger.info "Processing #{contacts.count} contacts for campaign #{campaign.id}"

    contacts.find_each { |contact| process_contact(contact) }

    Rails.logger.info "Campaign #{campaign.id} processing completed"
  end

  def process_contact(contact)
    recipient = campaign.campaign_recipients.create!(account: campaign.account, inbox: inbox, contact: contact)
    contact_inbox = campaign_contact_inbox(contact)
    template_params = contact_template_params(contact, contact_inbox)
    content = Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(campaign.message)

    recipient.update!(message_content: content)
    create_campaign_message(recipient, contact_inbox, content, template_params)
  rescue RecipientSkipped => e
    Rails.logger.warn "Skipping campaign #{campaign.id} recipient contact_id=#{contact.id}: #{e.message}"
    recipient.mark_skipped!(e.message)
  end

  def campaign_contact_inbox(contact)
    return ContactInboxBuilder.new(contact: contact, inbox: inbox).perform if contact.phone_number.present?

    bsuid_contact_inboxes = bsuid_contact_inboxes_for(contact)
    raise RecipientSkipped, 'Phone number and BSUID are missing' if bsuid_contact_inboxes.empty?
    raise RecipientSkipped, 'Multiple WhatsApp identities found; refusing to choose a destination' unless bsuid_contact_inboxes.one?

    bsuid_contact_inboxes.first
  end

  def contact_template_params(contact, contact_inbox)
    raise RecipientSkipped, 'Template parameters are missing' if campaign.template_params.blank?

    template_params = Whatsapp::LiquidTemplateProcessorService.new(campaign: campaign, contact: contact)
                                                              .process_template_params(campaign.template_params)
    raise RecipientSkipped, 'Template variables resolved to blank values' if template_params.nil?

    guard_error = Whatsapp::AuthenticationTemplateGuard.new(channel: channel, recipient: contact_inbox.source_id,
                                                            template_params: template_params).error
    raise RecipientSkipped, guard_error if guard_error

    template_params
  end

  # `campaign_recipient_id` ties the message to its recipient. Clients can name a campaign_id on a message through
  # Messages::MessageBuilder, but not this key, so only the campaign's own messages move a recipient.
  def create_campaign_message(recipient, contact_inbox, content, template_params)
    campaign_conversation(contact_inbox).messages.create!(
      account_id: campaign.account_id,
      inbox_id: inbox.id,
      message_type: :outgoing,
      sender: campaign.sender,
      content: content,
      additional_attributes: { 'campaign_id' => campaign.id, 'campaign_recipient_id' => recipient.id, 'template_params' => template_params }
    )
  end

  # The conversation the contact's reply lands in, found the way Whatsapp::IncomingMessageBaseService#set_conversation
  # finds it. A new one carries the campaign, so it starts pending with the inbox's AI agent or bot when the inbox has one.
  def campaign_conversation(contact_inbox)
    conversations = contact_inbox.conversations
    conversation = inbox.lock_to_single_conversation ? conversations.last : conversations.where.not(status: :resolved).last
    conversation || conversations.create!(account_id: campaign.account_id, inbox_id: inbox.id, contact_id: contact_inbox.contact_id,
                                          campaign: campaign)
  end

  def bsuid_contact_inboxes_for(contact)
    contact.contact_inboxes.where(inbox_id: inbox.id).select do |contact_inbox|
      bsuid_source_id?(contact_inbox.source_id)
    end
  end

  def bsuid_source_id?(source_id)
    source_id.to_s.delete_prefix('whatsapp:').match?(RegexHelper::WHATSAPP_BSUID_REGEX)
  end

  def whatsapp_cloud_channel?
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end
end

Whatsapp::OneoffCampaignService.prepend_mod_with('Whatsapp::OneoffCampaignService')

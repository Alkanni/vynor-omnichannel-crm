class CampaignListener < BaseListener
  def campaign_triggered(event)
    contact_inbox = event.data[:contact_inbox]
    campaign_display_id = event.data[:event_info][:campaign_id]
    custom_attributes = event.data[:event_info][:custom_attributes]

    return if campaign_display_id.blank?

    ::Campaigns::CampaignConversationBuilder.new(
      contact_inbox_id: contact_inbox.id,
      campaign_display_id: campaign_display_id,
      conversation_additional_attributes: event.data[:event_info].except(:campaign_id, :custom_attributes),
      custom_attributes: custom_attributes
    ).perform
  end

  # One-off campaign messages are sent by SendReplyJob and updated by WhatsApp status webhooks; the recipient follows them.
  def message_updated(event)
    message = event.data[:message]
    campaign_id = message.additional_attributes['campaign_id']
    return if campaign_id.blank?

    CampaignRecipient.find_by(campaign_id: campaign_id, contact_id: message.conversation.contact_id)&.sync_with_message!(message)
  end
end

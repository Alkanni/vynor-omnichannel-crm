class Webhooks::TelegramEventsJob < ApplicationJob
  queue_as :default
  # Arguments hold customer message payloads, and jobs enqueued before channel_id was introduced hold the bot token.
  self.log_arguments = false

  def perform(params = {})
    channel = find_channel(params)

    if channel_is_inactive?(channel)
      log_inactive_channel(channel, params)
      return
    end

    process_event_params(channel, params)
  end

  private

  def find_channel(params)
    return Channel::Telegram.find_by(id: params[:channel_id]) if params[:channel_id]

    # Jobs enqueued before the webhook secret change carry the bot token instead of the channel id.
    Channel::Telegram.find_by(bot_token: params[:bot_token])
  end

  def channel_is_inactive?(channel)
    return true if channel.blank?
    return true unless channel.account.active?

    false
  end

  def log_inactive_channel(channel, params)
    message = if channel&.id
                "Account #{channel.account.id} is not active for channel #{channel.id}"
              else
                "Channel not found for channel_id: #{params[:channel_id]}"
              end
    Rails.logger.warn("Telegram event discarded: #{message}")
  end

  def process_event_params(channel, params)
    return unless params[:telegram]

    if params.dig(:telegram, :edited_message).present? || params.dig(:telegram, :edited_business_message).present?
      Telegram::UpdateMessageService.new(inbox: channel.inbox, params: params['telegram'].with_indifferent_access).perform
    else
      Telegram::IncomingMessageService.new(inbox: channel.inbox, params: params['telegram'].with_indifferent_access).perform
    end
  end
end

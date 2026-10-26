# Re-registers Telegram webhooks created before webhook secrets existed, moving them off the
# token-bearing /webhooks/telegram/:bot_token URL and making Telegram send the secret header.
class Migration::RegisterTelegramWebhooksJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    Channel::Telegram.where(webhook_secret: nil).find_each do |channel|
      channel.save!
      Rails.logger.warn("[telegram-webhooks] re-registration failed for channel_id=#{channel.id}") if channel.webhook_secret.blank?
    end
  end
end

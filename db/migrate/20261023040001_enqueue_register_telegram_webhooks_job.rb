class EnqueueRegisterTelegramWebhooksJob < ActiveRecord::Migration[7.1]
  def up
    Migration::RegisterTelegramWebhooksJob.perform_later
  end

  def down; end
end

class AddWebhookSecretToChannelTelegram < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_telegram, :webhook_secret, :string
    add_index :channel_telegram, :webhook_secret, unique: true
  end
end

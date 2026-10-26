require 'rails_helper'

RSpec.describe Migration::RegisterTelegramWebhooksJob do
  let!(:legacy_channel) { create(:channel_telegram, bot_token: 'legacy_bot_token') }
  let!(:registered_channel) { create(:channel_telegram, bot_token: 'registered_bot_token', webhook_secret: 'existing-secret') }

  before do
    stub_request(:post, %r{api\.telegram\.org/botlegacy_bot_token/(deleteWebhook|setWebhook)})
      .to_return(status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'registers webhook secrets for channels that do not have one' do
    described_class.perform_now

    expect(legacy_channel.reload.webhook_secret).to be_present
    expect(registered_channel.reload.webhook_secret).to eq('existing-secret')
    expect(a_request(:post, /botregistered_bot_token/)).not_to have_been_made
  end
end

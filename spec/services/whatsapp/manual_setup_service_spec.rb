require 'rails_helper'

RSpec.describe Whatsapp::ManualSetupService do
  let(:account) { create(:account) }
  let(:preview) do
    { display_phone_number: '+15550001111', phone_number_id: 'phone-id', waba_id: 'waba-id', suggested_inbox_name: 'Test WhatsApp' }
  end
  let(:validation_service) { instance_double(Whatsapp::ManualSetupValidationService, perform: preview) }
  let(:webhook_setup) { instance_double(Whatsapp::WebhookSetupService, perform: true, registration_error: nil) }
  let(:provider_service) { instance_double(Whatsapp::Providers::WhatsappCloudService, validate_provider_config?: true, sync_templates: nil) }
  let(:setup_params) { { account: account, waba_id: 'waba-id', phone_number_id: 'phone-id', access_token: 'token' } }

  before do
    allow(Whatsapp::ManualSetupValidationService).to receive(:new).and_return(validation_service)
    allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(webhook_setup)
    allow(Whatsapp::Providers::WhatsappCloudService).to receive(:new).and_return(provider_service)
  end

  it 'stores the app secret in provider_config when provided' do
    channel = described_class.new(**setup_params, app_secret: 'meta-app-secret').perform.channel

    expect(channel.reload.provider_config).to include('source' => 'manual_setup_v2', 'app_secret' => 'meta-app-secret')
  end

  it 'does not store an app secret when none is provided' do
    channel = described_class.new(**setup_params).perform.channel

    expect(channel.reload.provider_config).not_to have_key('app_secret')
  end
end

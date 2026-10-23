require 'rails_helper'

RSpec.describe AiAgent::Integration do
  include_context 'with active record encryption'

  it 'stores the OAuth tokens encrypted' do
    integration = create(:ai_agent_integration)

    raw = integration.reload.read_attribute_before_type_cast(:credentials).to_s
    expect(raw).not_to include('ya29.access-token', '1//refresh-token')
    expect(integration.credentials['access_token']).to eq('ya29.access-token')
    expect(integration.account).to eq(integration.ai_agent.account)
  end

  it 'allows one integration of each type per agent' do
    integration = create(:ai_agent_integration)

    expect(build(:ai_agent_integration, ai_agent: integration.ai_agent)).not_to be_valid
  end

  it 'is writable only when connected with columns and a write condition' do
    integration = create(:ai_agent_integration)
    expect(integration).to be_writable

    integration.settings['when_to_write'] = ''
    expect(integration).not_to be_writable

    integration.settings['when_to_write'] = 'Saat booking lengkap'
    integration.needs_reconnect!
    expect(integration).not_to be_writable
  end
end

require 'rails_helper'

RSpec.describe 'AI agent Google Sheets OAuth callback', type: :request do
  include_context 'with active record encryption'

  let(:ai_agent) { create(:ai_agent) }
  let(:admin) { create(:user, account: ai_agent.account, role: :administrator) }
  let(:frontend_url) { ENV.fetch('FRONTEND_URL', 'http://localhost:3000') }
  let(:callback_url) { "#{frontend_url}/ai_agents/google_sheets/callback" }
  # Started like the dashboard does, so this browser holds the state cookie for the callback.
  let(:state) do
    post "/api/v1/accounts/#{ai_agent.account_id}/ai_agents/#{ai_agent.id}/google_sheets/authorization",
         headers: admin.create_new_auth_token, as: :json
    Rack::Utils.parse_query(URI.parse(response.parsed_body['url']).query)['state']
  end
  let(:integrations_url) { "#{frontend_url}/app/accounts/#{ai_agent.account_id}/ai-agents/#{ai_agent.id}/integrations" }
  let(:token_response) do
    { access_token: 'ya29.fresh', refresh_token: '1//fresh-refresh', expires_in: 3599, token_type: 'Bearer',
      id_token: JWT.encode({ email: 'sales@example.com' }, nil, 'none') }
  end

  before do
    # Google redirects to the FRONTEND_URL host, which also serves the dashboard API.
    host! URI.parse(frontend_url).authority
    create(:installation_config, name: 'GOOGLE_OAUTH_CLIENT_ID', value: 'google-client-id')
    stub_request(:post, 'https://accounts.google.com/o/oauth2/token')
      .with(body: hash_including('code' => 'auth-code', 'grant_type' => 'authorization_code',
                                 'redirect_uri' => "#{frontend_url}/ai_agents/google_sheets/callback"))
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: token_response.to_json)
  end

  it 'stores the tokens encrypted and the Google account, then returns to the Integrations tab' do
    get callback_url, params: { code: 'auth-code', state: state }

    expect(response).to redirect_to("#{integrations_url}?google_sheets=connected")
    expect(cookies[:ai_agent_google_sheets_state]).to be_blank
    integration = ai_agent.reload.google_sheets_integration
    expect(integration).to be_connected
    expect(integration.settings['email']).to eq('sales@example.com')
    expect(integration.credentials).to include('access_token' => 'ya29.fresh', 'refresh_token' => '1//fresh-refresh')
    expect(integration.read_attribute_before_type_cast(:credentials)).not_to include('ya29.fresh')
  end

  it 'reconnects an integration that needed it and keeps its sheet settings' do
    create(:ai_agent_integration, ai_agent: ai_agent, status: :needs_reconnect)

    get callback_url, params: { code: 'auth-code', state: state }

    integration = ai_agent.reload.google_sheets_integration
    expect(integration).to be_connected
    expect(integration.settings).to include('sheet_name' => 'Booking', 'email' => 'sales@example.com')
  end

  it 'rejects an invalid or foreign state without saving anything' do
    state
    [ai_agent.to_sgid(expires_in: 15.minutes).to_s, ai_agent.account.to_sgid(for: 'ai_agent_google_sheets').to_s, 'forged'].each do |bad_state|
      get callback_url, params: { code: 'auth-code', state: bad_state }

      expect(response).to have_http_status(:bad_request)
    end
    expect(AiAgent::Integration.count).to eq(0)
  end

  it 'rejects a valid state that comes back to a browser which did not start the flow' do
    leaked_state = ai_agent.to_sgid(expires_in: 15.minutes, for: 'ai_agent_google_sheets').to_s

    get callback_url, params: { code: 'auth-code', state: leaked_state }

    expect(response).to have_http_status(:bad_request)
    expect(ai_agent.reload.google_sheets_integration).to be_nil
  end

  it 'returns to the Integrations tab with an error when the admin declined consent' do
    get callback_url, params: { error: 'access_denied', state: state }

    expect(response).to redirect_to("#{integrations_url}?google_sheets=error")
    expect(ai_agent.reload.google_sheets_integration).to be_nil
  end
end

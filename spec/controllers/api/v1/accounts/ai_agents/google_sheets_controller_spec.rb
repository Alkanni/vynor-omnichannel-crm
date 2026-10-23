require 'rails_helper'

RSpec.describe 'AI agent Google Sheets API', type: :request do
  include_context 'with active record encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/google_sheets" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:sheet) { { spreadsheet_url: 'https://docs.google.com/spreadsheets/d/sheet-456/edit#gid=0', sheet_name: 'Order' } }
  let(:header_url) { "https://sheets.googleapis.com/v4/spreadsheets/sheet-456/values/#{ERB::Util.url_encode("'Order'!1:1")}" }

  before { create(:installation_config, name: 'GOOGLE_OAUTH_CLIENT_ID', value: 'google-client-id') }

  describe 'GET show' do
    it 'describes the connection without exposing tokens' do
      create(:ai_agent_integration, ai_agent: ai_agent)

      get url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('available' => true, 'connected' => true, 'status' => 'connected', 'email' => 'owner@example.com',
                                              'columns' => ['Nama', '', 'Tanggal'])
      expect(response.body).not_to include('ya29.access-token', '1//refresh-token')
    end

    it 'returns unauthorized for agents' do
      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST authorization' do
    it 'returns the Google consent URL with a signed state for the agent' do
      post "#{url}/authorization", headers: admin.create_new_auth_token, as: :json

      consent = URI.parse(response.parsed_body['url'])
      query = Rack::Utils.parse_query(consent.query)
      expect(consent.host).to eq('accounts.google.com')
      expect(query).to include('access_type' => 'offline', 'prompt' => 'consent', 'client_id' => 'google-client-id',
                               'scope' => 'email https://www.googleapis.com/auth/spreadsheets')
      expect(query['redirect_uri']).to end_with('/ai_agents/google_sheets/callback')
      expect(GlobalID::Locator.locate_signed(query['state'], for: 'ai_agent_google_sheets')).to eq(ai_agent)
    end

    it 'refuses when the installation has no encryption keys' do
      with_modified_env(ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY: nil) do
        post "#{url}/authorization", headers: admin.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('encryption keys')
    end
  end

  describe 'POST test_connection' do
    before { create(:ai_agent_integration, ai_agent: ai_agent) }

    it 'returns the header row of the sheet' do
      stub_request(:get, header_url).to_return(status: 200, headers: json, body: { values: [%w[Nama Produk Jumlah]] }.to_json)

      post "#{url}/test_connection", params: sheet, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('columns' => %w[Nama Produk Jumlah])
    end

    it 'explains spreadsheets without access, invalid URLs, and empty header rows' do
      stub_request(:get, header_url).to_return({ status: 403, headers: json, body: '{}' }, { status: 200, headers: json, body: '{}' })

      post "#{url}/test_connection", params: sheet, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['error']).to include('denied access')

      post "#{url}/test_connection", params: sheet, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['error']).to include('first row of the sheet is empty')

      invalid_url = sheet.merge(spreadsheet_url: 'https://example.com/sheet')
      post "#{url}/test_connection", params: invalid_url, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('docs.google.com/spreadsheets')
    end
  end

  describe 'PATCH update' do
    it 'saves the sheet with the columns read from Google, not from the request' do
      integration = create(:ai_agent_integration, ai_agent: ai_agent)
      stub_request(:get, header_url).to_return(status: 200, headers: json, body: { values: [%w[Nama Produk]] }.to_json)

      patch url, params: sheet.merge(when_to_write: 'Saat order lengkap', columns: ['Injected']), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(integration.reload.settings).to include('spreadsheet_id' => 'sheet-456', 'sheet_name' => 'Order', 'columns' => %w[Nama Produk],
                                                     'when_to_write' => 'Saat order lengkap', 'email' => 'owner@example.com')
    end

    it 'requires a connected integration' do
      patch url, params: sheet, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Connect Google Sheets first')
    end
  end

  describe 'DELETE destroy' do
    it 'revokes the grant and removes the tokens, even when Google already dropped the grant' do
      create(:ai_agent_integration, ai_agent: ai_agent)
      revoke = stub_request(:post, 'https://oauth2.googleapis.com/revoke').with(body: { token: '1//refresh-token' })
                                                                          .to_return(status: 400, headers: json, body: '{}')

      delete url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(revoke).to have_been_requested
      expect(ai_agent.reload.google_sheets_integration).to be_nil
    end
  end
end

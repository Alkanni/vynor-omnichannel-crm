require 'rails_helper'

RSpec.describe AiAgents::GoogleSheetsClient do
  include_context 'with active record encryption'

  let(:integration) { create(:ai_agent_integration) }
  let(:client) { described_class.new(integration) }
  let(:header_url) { "https://sheets.googleapis.com/v4/spreadsheets/sheet-123/values/#{ERB::Util.url_encode("'Booking'!1:1")}" }
  let(:json) { { 'Content-Type' => 'application/json' } }

  it 'reads the header row with the stored access token' do
    stub_request(:get, header_url).with(headers: { 'Authorization' => 'Bearer ya29.access-token' })
                                  .to_return(status: 200, headers: json, body: { values: [['Nama', '', ' Tanggal ']] }.to_json)

    expect(client.header_row(spreadsheet_id: 'sheet-123', sheet_name: 'Booking')).to eq(['Nama', '', 'Tanggal'])
  end

  it 'appends rows as raw values so customer text is never run as a formula' do
    append = stub_request(:post, "https://sheets.googleapis.com/v4/spreadsheets/sheet-123/values/#{ERB::Util.url_encode("'Booking'!A1")}:append")
             .with(query: { valueInputOption: 'RAW', insertDataOption: 'INSERT_ROWS' }, body: { values: [['Budi', '', '=1+1']] }.to_json)
             .to_return(status: 200, headers: json, body: '{}')

    client.append_row(['Budi', '', '=1+1'])

    expect(append).to have_been_requested
  end

  it 'refreshes an expiring token and keeps the refresh token Google did not resend' do
    integration.update!(credentials: integration.credentials.merge('expires_at' => 2.minutes.from_now.to_i))
    stub_request(:post, 'https://accounts.google.com/o/oauth2/token')
      .with(body: hash_including('grant_type' => 'refresh_token', 'refresh_token' => '1//refresh-token'))
      .to_return(status: 200, headers: json, body: { access_token: 'ya29.new-token', expires_in: 3600, token_type: 'Bearer' }.to_json)
    stub_request(:get, header_url).with(headers: { 'Authorization' => 'Bearer ya29.new-token' })
                                  .to_return(status: 200, headers: json, body: { values: [['Nama']] }.to_json)

    client.header_row(spreadsheet_id: 'sheet-123', sheet_name: 'Booking')

    credentials = integration.reload.credentials
    expect(credentials).to include('access_token' => 'ya29.new-token', 'refresh_token' => '1//refresh-token')
    expect(credentials['expires_at']).to be > 50.minutes.from_now.to_i
  end

  it 'asks for a reconnect when the grant was revoked' do
    integration.update!(credentials: integration.credentials.merge('expires_at' => 1.minute.ago.to_i))
    stub_request(:post, 'https://accounts.google.com/o/oauth2/token')
      .to_return(status: 400, headers: json, body: { error: 'invalid_grant' }.to_json)

    expect { client.header_row(spreadsheet_id: 'sheet-123', sheet_name: 'Booking') }
      .to raise_error(AiAgents::GoogleSheetsError, /Reconnect Google Sheets/)
    expect(integration.reload).to be_needs_reconnect
  end

  it 'explains a spreadsheet without access without asking for a reconnect' do
    stub_request(:get, header_url).to_return(status: 403, headers: json, body: { error: { message: 'The caller does not have permission' } }.to_json)

    expect { client.header_row(spreadsheet_id: 'sheet-123', sheet_name: 'Booking') }
      .to raise_error(an_instance_of(AiAgents::GoogleSheetsError).and(having_attributes(status: 403, message: /denied access/)))
    expect(integration.reload).to be_connected
  end
end

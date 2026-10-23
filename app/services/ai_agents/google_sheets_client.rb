# Google Sheets access for an AI agent integration: keeps its OAuth token fresh and makes the Sheets API calls the
# AI agent needs. A revoked grant marks the integration needs_reconnect.
class AiAgents::GoogleSheetsClient
  include GoogleConcern

  SHEETS_API = 'https://sheets.googleapis.com/v4/spreadsheets'.freeze
  REVOKE_URL = 'https://oauth2.googleapis.com/revoke'.freeze
  REFRESH_WINDOW = 5.minutes

  pattr_initialize :integration

  def header_row(spreadsheet_id:, sheet_name:)
    response = request(:get, "#{SHEETS_API}/#{spreadsheet_id}/values/#{range(sheet_name, '1:1')}")
    Array(response.parsed['values']&.first).map { |value| value.to_s.strip }
  end

  # RAW keeps customer text such as "=SUM(...)" from being evaluated as a formula.
  def append_row(values)
    settings = integration.settings
    request(:post, "#{SHEETS_API}/#{settings['spreadsheet_id']}/values/#{range(settings['sheet_name'], 'A1')}:append",
            params: { valueInputOption: 'RAW', insertDataOption: 'INSERT_ROWS' },
            headers: { 'Content-Type' => 'application/json' }, body: { values: [values] }.to_json)
  end

  def revoke
    google_client.request(:post, REVOKE_URL, body: { token: credentials['refresh_token'] })
  end

  private

  def request(verb, url, **)
    access_token.public_send(verb, url, **)
  rescue OAuth2::Error => e
    status = e.response&.status
    integration.needs_reconnect! if status == 401
    raise AiAgents::GoogleSheetsError.new(I18n.t("ai_agents.google_sheets.errors.#{error_key(status)}"), status: status)
  end

  def access_token
    token = OAuth2::AccessToken.new(google_client, credentials['access_token'],
                                    refresh_token: credentials['refresh_token'], expires_at: credentials['expires_at'])
    return token if token.expires_at.to_i > REFRESH_WINDOW.from_now.to_i

    refresh(token)
  end

  def refresh(token)
    token = token.refresh!
    integration.update!(credentials: { 'access_token' => token.token, 'refresh_token' => token.refresh_token,
                                       'expires_at' => token.expires_at })
    token
  rescue OAuth2::Error
    integration.needs_reconnect!
    raise AiAgents::GoogleSheetsError, I18n.t('ai_agents.google_sheets.errors.reconnect')
  end

  def error_key(status)
    case status
    when 401 then 'reconnect'
    when 403 then 'forbidden'
    when 400, 404 then 'not_found'
    else 'request_failed'
    end
  end

  def range(sheet_name, cells)
    ERB::Util.url_encode("'#{sheet_name.gsub("'", "''")}'!#{cells}")
  end

  def credentials
    integration.credentials
  end
end

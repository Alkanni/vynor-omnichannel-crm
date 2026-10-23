integration = @ai_agent.google_sheets_integration
json.available Api::V1::Accounts::AiAgents::GoogleSheetsController.available?
json.connected integration.present?
if integration
  json.status integration.status
  json.email integration.settings['email']
  json.spreadsheet_url integration.settings['spreadsheet_url']
  json.sheet_name integration.settings['sheet_name']
  json.columns integration.settings['columns'] || []
  json.when_to_write integration.settings['when_to_write']
end

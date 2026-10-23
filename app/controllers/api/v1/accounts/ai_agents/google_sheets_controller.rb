class Api::V1::Accounts::AiAgents::GoogleSheetsController < Api::V1::Accounts::AiAgents::BaseController
  include AiAgentGoogleSheetsConcern

  InvalidSettings = Class.new(StandardError)

  SPREADSHEET_URL = %r{\Ahttps://docs\.google\.com/spreadsheets/d/([\w-]+)}
  MAX_SHEET_NAME_LENGTH = 100
  MAX_WHEN_TO_WRITE_LENGTH = 3_000

  before_action :fetch_integration, only: [:update, :test_connection, :destroy]

  rescue_from AiAgents::GoogleSheetsError, InvalidSettings do |error|
    render_could_not_create_error(error.message)
  end

  def show; end

  def authorization
    raise InvalidSettings, I18n.t('ai_agents.google_sheets.errors.unavailable') unless self.class.available?

    url = google_client.auth_code.authorize_url(
      redirect_uri: google_sheets_redirect_uri, scope: scope, access_type: 'offline', prompt: 'consent', state: issue_state(@ai_agent)
    )
    render json: { url: url }
  end

  def test_connection
    render json: { columns: header_row(sheet_params) }
  end

  # The columns come from the sheet's header row at save time, never from the client.
  def update
    sheet = sheet_params
    raise InvalidSettings, I18n.t('ai_agents.google_sheets.errors.when_to_write_too_long') if when_to_write.length > MAX_WHEN_TO_WRITE_LENGTH

    @integration.update!(settings: @integration.settings.merge(sheet, 'columns' => header_row(sheet), 'when_to_write' => when_to_write))
    render :show
  end

  # Disconnecting always removes the tokens; a failed revoke (e.g. a grant the user already removed) is only reported.
  def destroy
    begin
      AiAgents::GoogleSheetsClient.new(@integration).revoke
    rescue OAuth2::Error, Faraday::Error => e
      ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
    end
    @integration.destroy!
    head :ok
  end

  def self.available?
    Chatwoot.encryption_configured? && GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil).present?
  end

  private

  def fetch_integration
    @integration = @ai_agent.google_sheets_integration
    raise InvalidSettings, I18n.t('ai_agents.google_sheets.errors.not_connected') if @integration.blank?
  end

  def sheet_params
    spreadsheet_id = params[:spreadsheet_url].to_s[SPREADSHEET_URL, 1]
    sheet_name = params[:sheet_name].to_s.strip
    raise InvalidSettings, I18n.t('ai_agents.google_sheets.errors.invalid_url') if spreadsheet_id.blank?
    if sheet_name.blank? || sheet_name.length > MAX_SHEET_NAME_LENGTH
      raise InvalidSettings, I18n.t('ai_agents.google_sheets.errors.invalid_sheet_name')
    end

    { 'spreadsheet_url' => params[:spreadsheet_url], 'spreadsheet_id' => spreadsheet_id, 'sheet_name' => sheet_name }
  end

  def header_row(sheet)
    columns = AiAgents::GoogleSheetsClient.new(@integration).header_row(spreadsheet_id: sheet['spreadsheet_id'], sheet_name: sheet['sheet_name'])
    raise InvalidSettings, I18n.t('ai_agents.google_sheets.errors.empty_header') if columns.none?(&:present?)

    columns
  end

  def when_to_write
    params[:when_to_write].to_s.strip
  end
end

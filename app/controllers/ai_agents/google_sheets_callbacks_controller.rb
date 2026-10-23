# Google redirects here after the admin consents to Google Sheets access for an AI agent. The signed state names
# the agent and must come back to the browser that requested it; tokens are stored encrypted and never leave the server.
class AiAgents::GoogleSheetsCallbacksController < ApplicationController
  include AiAgentGoogleSheetsConcern

  def show
    ai_agent = GlobalID::Locator.locate_signed(params[:state].to_s, for: STATE_PURPOSE)
    return head :bad_request unless ai_agent.is_a?(AiAgent) && state_from_this_browser?

    cookies.delete(STATE_COOKIE)
    connect(ai_agent) if params[:code].present?
    redirect_to integrations_url(ai_agent, params[:code].present? ? 'connected' : 'error')
  rescue OAuth2::Error => e
    ChatwootExceptionTracker.new(e, account: ai_agent.account).capture_exception
    redirect_to integrations_url(ai_agent, 'error')
  end

  private

  def connect(ai_agent)
    token = google_client.auth_code.get_token(params[:code], redirect_uri: google_sheets_redirect_uri)
    email = JWT.decode(token.params['id_token'], nil, false).first['email']
    integration = ai_agent.google_sheets_integration || ai_agent.build_google_sheets_integration
    integration.update!(
      status: :connected, settings: integration.settings.merge('email' => email),
      credentials: { 'access_token' => token.token, 'refresh_token' => token.refresh_token, 'expires_at' => token.expires_at }
    )
  end

  def integrations_url(ai_agent, result)
    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/app/accounts/#{ai_agent.account_id}/ai-agents/#{ai_agent.id}/integrations" \
      "?google_sheets=#{result}"
  end
end

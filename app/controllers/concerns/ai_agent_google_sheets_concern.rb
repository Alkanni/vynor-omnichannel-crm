# Google OAuth for an AI agent's Google Sheets integration (authorization request and its callback).
module AiAgentGoogleSheetsConcern
  extend ActiveSupport::Concern
  include GoogleConcern

  STATE_PURPOSE = 'ai_agent_google_sheets'.freeze
  STATE_COOKIE = :ai_agent_google_sheets_state
  STATE_TTL = 15.minutes

  private

  # The signed state names the AI agent; a digest of it in an encrypted cookie ties the callback to the browser that
  # started the flow, so a leaked state cannot connect another Google account.
  def issue_state(ai_agent)
    state = ai_agent.to_sgid(expires_in: STATE_TTL, for: STATE_PURPOSE).to_s
    cookies.encrypted[STATE_COOKIE] = { value: state_digest(state), expires: STATE_TTL, httponly: true, same_site: :lax, secure: request.ssl? }
    state
  end

  def state_from_this_browser?
    expected = cookies.encrypted[STATE_COOKIE]
    expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, state_digest(params[:state].to_s))
  end

  def state_digest(state)
    Digest::SHA256.hexdigest(state)
  end

  def scope
    'email https://www.googleapis.com/auth/spreadsheets'
  end

  def google_sheets_redirect_uri
    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/ai_agents/google_sheets/callback"
  end
end

# Google OAuth for an AI agent's Google Sheets integration (authorization request and its callback).
module AiAgentGoogleSheetsConcern
  extend ActiveSupport::Concern
  include GoogleConcern

  STATE_PURPOSE = 'ai_agent_google_sheets'.freeze

  private

  def scope
    'email https://www.googleapis.com/auth/spreadsheets'
  end

  def google_sheets_redirect_uri
    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/ai_agents/google_sheets/callback"
  end
end

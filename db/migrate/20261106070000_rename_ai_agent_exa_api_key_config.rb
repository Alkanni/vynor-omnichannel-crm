# AI Agent web search can use other providers than Exa (#126), so the Exa API key becomes the key of the selected provider,
# which stays Exa until changed (AI_AGENT_WEB_SEARCH_PROVIDER defaults to exa).
class RenameAiAgentExaApiKeyConfig < ActiveRecord::Migration[7.1]
  def up
    InstallationConfig.find_by(name: 'AI_AGENT_EXA_API_KEY')&.update!(name: 'AI_AGENT_WEB_SEARCH_API_KEY')
  end

  def down
    InstallationConfig.find_by(name: 'AI_AGENT_WEB_SEARCH_API_KEY')&.update!(name: 'AI_AGENT_EXA_API_KEY')
  end
end

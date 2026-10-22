class Api::V1::Accounts::AiAgents::BaseController < Api::V1::Accounts::BaseController
  before_action :fetch_ai_agent

  private

  def fetch_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
    authorize @ai_agent, :update?
  end
end

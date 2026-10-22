class Api::V1::Accounts::AiAgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_ai_agent, except: [:index, :create]
  before_action :check_authorization

  def index
    @ai_agents = Current.account.ai_agents.order(created_at: :desc)
  end

  def show; end

  def create
    @ai_agent = Current.account.ai_agents.create!(permitted_params)
  end

  def update
    @ai_agent.update!(permitted_params)
  end

  def destroy
    @ai_agent.destroy!
    head :ok
  end

  def duplicate
    @ai_agent = @ai_agent.duplicate!
  end

  private

  def fetch_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:id])
  end

  def permitted_params
    params.require(:ai_agent).permit(
      :name, :behavior, :welcome_message, :transfer_conditions,
      :stop_ai_after_handoff, :silent_handoff, :pending_assigned_message, :pending_unassigned_message,
      :label_conditions, :model, :history_limit, :read_file_limit, :context_limit, :temperature,
      :message_await, :message_limit, :watcher_enabled, :timezone, :session_only_memory, :ignore_team_handoff,
      allowed_label_ids: []
    )
  end
end

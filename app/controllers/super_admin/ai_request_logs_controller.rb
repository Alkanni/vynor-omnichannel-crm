# Read-only viewer of the AI Agent request logs (see AiAgent::RequestLog): a filtered list of the runs, newest first, and one
# run with the input and output of each of its steps.
class SuperAdmin::AiRequestLogsController < SuperAdmin::ApplicationController
  COLUMN_FILTERS = %i[account_id ai_agent_id source status].freeze
  # conversation is the number of a conversation in the dashboard; from and to are dates (YYYY-MM-DD, UTC).
  FILTERS = [*COLUMN_FILTERS, :conversation, :from, :to].freeze

  rescue_from Date::Error, with: -> { head :unprocessable_entity }

  def index
    @filters = params.slice(*FILTERS).permit(*FILTERS).compact_blank
    @logs = filtered_logs.summaries.includes(:account, :ai_agent, :conversation).order(created_at: :desc, id: :desc).page(params[:page])
    @ai_agents = AiAgent.includes(:account).order(:account_id, :name)
  end

  def show
    @log = AiAgent::RequestLog.find(params[:id])
  end

  private

  def filtered_logs
    logs = AiAgent::RequestLog.where(@filters.slice(*COLUMN_FILTERS).to_h)
    logs = logs.where(conversation_id: Conversation.where(display_id: @filters[:conversation]).select(:id)) if @filters[:conversation]
    logs = logs.where(created_at: Date.iso8601(@filters[:from]).beginning_of_day..) if @filters[:from]
    logs = logs.where(created_at: ..Date.iso8601(@filters[:to]).end_of_day) if @filters[:to]
    logs
  end
end

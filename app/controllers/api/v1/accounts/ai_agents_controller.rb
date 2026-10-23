class Api::V1::Accounts::AiAgentsController < Api::V1::Accounts::BaseController
  SETTINGS = %w[
    name behavior welcome_message transfer_conditions stop_ai_after_handoff silent_handoff pending_assigned_message
    pending_unassigned_message label_conditions model history_limit read_file_limit context_limit temperature
    message_await message_limit watcher_enabled timezone session_only_memory ignore_team_handoff
  ].freeze
  LIST_SETTINGS = %w[allowed_label_ids inbox_ids].freeze
  MAX_PLAYGROUND_MESSAGES = 100
  MAX_PLAYGROUND_MESSAGE_LENGTH = 10_000
  PLAYGROUND_ROLES = %w[user assistant].freeze

  # inbox_ids is not a column, so the default JSON wrapping into ai_agent would drop it.
  wrap_parameters :ai_agent, include: SETTINGS + LIST_SETTINGS

  before_action :fetch_ai_agent, except: [:index, :create]
  before_action :check_authorization
  before_action :validate_inbox_ids, only: [:create, :update]

  def index
    @ai_agents = Current.account.ai_agents.includes(:inboxes).order(created_at: :desc)
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

  def train
    @ai_agent.schedule_training
    head :accepted
  end

  def playground
    messages = playground_messages
    return render_could_not_create_error('Invalid messages') if messages.nil?

    render json: { messages: AiAgents::ReplyGenerator.new(ai_agent: @ai_agent, messages: messages.last(@ai_agent.history_limit)).perform }
  rescue AiAgents::LlmError => e
    render_could_not_create_error(e.message)
  end

  private

  def fetch_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:id])
  end

  def permitted_params
    params.require(:ai_agent).permit(*SETTINGS, LIST_SETTINGS.index_with { [] })
  end

  # inbox_ids= finds inboxes across all accounts, so ids outside this account are rejected before the
  # connection validations run and could echo another account's inbox or agent names.
  def validate_inbox_ids
    inbox_ids = params.dig(:ai_agent, :inbox_ids)
    return if inbox_ids.nil?
    return if inbox_ids.is_a?(Array) && Current.account.inboxes.where(id: inbox_ids).count == inbox_ids.uniq.size

    render_could_not_create_error(I18n.t('ai_agents.inboxes.errors.invalid'))
  end

  # Returns nil unless every message is a non-empty user or assistant text within the playground limits.
  def playground_messages
    messages = params.require(:messages)
    return unless messages.is_a?(Array) && messages.size <= MAX_PLAYGROUND_MESSAGES && messages.all? { |message| playground_message?(message) }

    messages.map { |message| { role: message[:role].to_sym, content: message[:content] } }
  end

  def playground_message?(message)
    message.is_a?(ActionController::Parameters) && PLAYGROUND_ROLES.include?(message[:role]) && message[:content].is_a?(String) &&
      message[:content].strip.present? && message[:content].length <= MAX_PLAYGROUND_MESSAGE_LENGTH
  end
end

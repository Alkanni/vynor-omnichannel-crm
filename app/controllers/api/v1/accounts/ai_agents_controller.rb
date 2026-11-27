class Api::V1::Accounts::AiAgentsController < Api::V1::Accounts::BaseController
  SETTINGS = %w[
    name behavior welcome_message transfer_conditions stop_ai_after_handoff silent_handoff pending_assigned_message
    pending_unassigned_message label_conditions model history_limit read_file_limit context_limit context_expansion_radius temperature
    message_await message_limit watcher_enabled timezone session_only_memory ignore_team_handoff
    scope_mode business_description allowed_topics disallowed_topics off_topic_message clarification_message knowledge_gap_message
    web_search_enabled web_search_domains booking_enabled booking_conditions booking_label_id booking_confirmed_message
    booking_cancelled_message booking_summary_template promotion_offers_enabled
  ].freeze
  LIST_SETTINGS = %w[allowed_label_ids inbox_ids booking_services].freeze
  MAX_PLAYGROUND_MESSAGES = 100
  MAX_PLAYGROUND_MESSAGE_LENGTH = 10_000
  PLAYGROUND_ROLES = %w[user assistant].freeze
  # Rack::Timeout ends a request after 15 s, so a playground reply leaves a second for the rest of the request (#145).
  PLAYGROUND_REPLY_DEADLINE_MS = 14_000

  # inbox_ids is not a column, so the default JSON wrapping into ai_agent would drop it.
  wrap_parameters :ai_agent, include: [*SETTINGS, *LIST_SETTINGS, 'booking_fields']

  before_action :fetch_ai_agent, except: [:index, :create, :models]
  before_action :check_authorization
  before_action :validate_inbox_ids, only: [:create, :update]
  before_action :validate_web_query, only: :retrieval_test

  def index
    @ai_agents = Current.account.ai_agents.includes(:inboxes).order(created_at: :desc)
  end

  def show; end

  def models
    render json: { models: AiAgent.available_models }
  end

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
    messages = conversation_messages(params.require(:messages))
    return render_could_not_create_error('Invalid messages') if messages.nil?

    messages = messages.last(@ai_agent.history_limit)
    @reply = AiAgents::RequestRecorder.record(ai_agent: @ai_agent, source: :playground, input: { messages: messages }) do |log|
      reply = AiAgents::ReplyGenerator.new(ai_agent: @ai_agent, messages: messages, deadline_ms: PLAYGROUND_REPLY_DEADLINE_MS).perform
      log.output = { messages: reply.messages, **reply.actions, booking_summary_rejection: reply.booking_summary_rejection }
      reply
    end
  rescue AiAgents::LlmError => e
    render_could_not_create_error(e.message)
  end

  # Searches the knowledge for a customer question exactly as a reply would (see AiAgents::KnowledgeRetriever), after the
  # optional history of earlier messages, in the format of the playground. An optional web query is also searched on the
  # web within the agent's domains, as a reply would (see AiAgents::WebSearch), so admins can judge the results before
  # customers see any.
  def retrieval_test
    query = params[:query]
    history = conversation_messages(params.fetch(:history, []))
    return render_could_not_create_error('Invalid query') unless query_text?(query, AiAgents::KnowledgeRetriever::MAX_QUERY_CHARACTERS)
    return render_could_not_create_error('Invalid history') if history.nil?

    search([*history, { role: :user, content: query }].last(@ai_agent.history_limit), params[:web_query])
  rescue AiAgents::LlmError => e
    render_could_not_create_error(e.message)
  end

  private

  # The search of a Retrieval Test, as a run of the request log (see AiAgents::RequestRecorder).
  def search(messages, web_query)
    AiAgents::RequestRecorder.record(ai_agent: @ai_agent, source: :retrieval_test, input: { messages: messages, web_query: web_query }) do |log|
      @retrieval = AiAgents::KnowledgeRetriever.new(ai_agent: @ai_agent, messages: messages).perform
      @web_search = AiAgents::WebSearch.new(query: web_query.strip, domains: @ai_agent.web_search_domain_list).perform if web_query
      log.output = { hits: @retrieval.hits.size, web_search_status: @web_search&.status }
    end
  end

  def fetch_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:id])
  end

  # Booking fields are objects that AiAgent::BookingFields checks whole, so a key it does not know is rejected, not dropped.
  def permitted_params
    settings = params.require(:ai_agent)
    settings.permit(*SETTINGS, LIST_SETTINGS.index_with { [] }).to_h.merge(settings.to_unsafe_h.slice(:booking_fields))
  end

  # inbox_ids= finds inboxes across all accounts, so ids outside this account are rejected before the
  # connection validations run and could echo another account's inbox or agent names.
  def validate_inbox_ids
    inbox_ids = params.dig(:ai_agent, :inbox_ids)
    return if inbox_ids.nil?
    return if inbox_ids.is_a?(Array) && Current.account.inboxes.where(id: inbox_ids).count == inbox_ids.uniq.size

    render_could_not_create_error(I18n.t('ai_agents.inboxes.errors.invalid'))
  end

  def validate_web_query
    web_query = params[:web_query]
    return if web_query.nil?
    return render_could_not_create_error('Invalid web query') unless query_text?(web_query, AiAgents::WebSearch::MAX_QUERY_CHARACTERS)

    render_could_not_create_error(I18n.t('ai_agents.web_search.errors.not_configured')) unless AiAgents::WebSearch.configured?
  end

  # Returns nil unless every message is a non-empty user or assistant text within the playground limits.
  def conversation_messages(messages)
    return unless messages.is_a?(Array) && messages.size <= MAX_PLAYGROUND_MESSAGES && messages.all? { |message| conversation_message?(message) }

    messages.map { |message| { role: message[:role].to_sym, content: message[:content] } }
  end

  def query_text?(value, max_length)
    value.is_a?(String) && value.strip.present? && value.length <= max_length
  end

  def conversation_message?(message)
    message.is_a?(ActionController::Parameters) && PLAYGROUND_ROLES.include?(message[:role]) && message[:content].is_a?(String) &&
      message[:content].strip.present? && message[:content].length <= MAX_PLAYGROUND_MESSAGE_LENGTH
  end
end

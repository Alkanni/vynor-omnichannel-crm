class Api::V1::Accounts::AiAgents::KnowledgeSourcesController < Api::V1::Accounts::AiAgents::BaseController
  before_action :fetch_knowledge_source, only: [:update, :destroy]

  def index
    source_type = params.require(:source_type)
    return render_could_not_create_error('Invalid source_type') unless AiAgent::KnowledgeSource.source_types.key?(source_type)

    @knowledge_sources = @ai_agent.knowledge_sources.where(source_type: source_type).order(id: source_type == 'qa' ? :desc : :asc)
  end

  def create
    @knowledge_source = @ai_agent.knowledge_sources.create!(params.permit(:source_type, :title, :content))
  end

  def update
    @knowledge_source.update!(params.permit(:title, :content))
  end

  def destroy
    @knowledge_source.destroy!
    head :ok
  end

  def stats
    render json: @ai_agent.knowledge_stats
  end

  private

  def fetch_knowledge_source
    @knowledge_source = @ai_agent.knowledge_sources.find(params[:id])
  end
end

class Api::V1::Accounts::AiAgents::KnowledgeSourcesController < Api::V1::Accounts::AiAgents::BaseController
  MAX_WEBSITES_PER_REQUEST = AiAgents::LinkCollector::MAX_LINKS

  before_action :fetch_knowledge_source, only: [:update, :destroy, :resync]

  def index
    source_type = params.require(:source_type)
    return render_could_not_create_error('Invalid source_type') unless AiAgent::KnowledgeSource.source_types.key?(source_type)

    @knowledge_sources = @ai_agent.knowledge_sources.where(source_type: source_type).order(id: source_type == 'text' ? :asc : :desc)
  end

  def create
    @knowledge_source = @ai_agent.knowledge_sources.create!(params.permit(:source_type, :title, :content, :file))
  end

  def update
    @knowledge_source.update!(params.permit(:title, :content))
  end

  def destroy
    @knowledge_source.destroy!
    head :ok
  end

  def bulk_destroy
    @ai_agent.knowledge_sources.where(id: params.require(:ids)).destroy_all
    head :ok
  end

  def stats
    render json: @ai_agent.knowledge_stats
  end

  def collect_links
    render json: { links: AiAgents::LinkCollector.new(params.require(:url)).perform }
  rescue AiAgents::ExtractionError => e
    render_could_not_create_error(e.message)
  end

  def websites
    urls = Array(params.require(:urls)).map { |url| url.to_s.strip }.uniq
    if urls.size > MAX_WEBSITES_PER_REQUEST
      return render_could_not_create_error("A maximum of #{MAX_WEBSITES_PER_REQUEST} links can be added at once")
    end

    existing_urls = @ai_agent.knowledge_sources.website.where(external_url: urls).pluck(:external_url)
    ActiveRecord::Base.transaction do
      @knowledge_sources = (urls - existing_urls).map do |url|
        @ai_agent.knowledge_sources.create!(source_type: :website, external_url: url)
      end
    end
    render :index
  end

  def resync
    unless @knowledge_source.website? || @knowledge_source.file?
      return render_could_not_create_error('Only website and file sources can be synced again')
    end

    @knowledge_source.resync!
    render :update
  end

  private

  def fetch_knowledge_source
    @knowledge_source = @ai_agent.knowledge_sources.find(params[:id])
  end
end

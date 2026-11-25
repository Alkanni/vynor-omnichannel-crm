class Api::V1::Accounts::AiAgents::PromotionsController < Api::V1::Accounts::AiAgents::BaseController
  before_action :fetch_promotion, only: [:update, :destroy]
  before_action :fetch_products, only: [:create, :update]

  def index
    status = params[:status]
    return render_could_not_create_error('Invalid status') if status.present? && AiAgent::Promotion::STATUSES.exclude?(status)

    @current_date = @ai_agent.current_date
    @promotions = @ai_agent.promotions.includes(:products).order(id: :desc)
    @promotions = @promotions.status_on(status, @current_date) if status.present?
    @promotions = @promotions.where('title ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%") if params[:q].present?
  end

  def create
    @promotion = @ai_agent.promotions.create!(promotion_params)
  end

  def update
    @promotion.update!(promotion_params)
  end

  def destroy
    @promotion.destroy!
    head :ok
  end

  def bulk_destroy
    @ai_agent.promotions.where(id: params.require(:ids)).destroy_all
    head :ok
  end

  private

  def fetch_promotion
    @promotion = @ai_agent.promotions.find(params[:id])
  end

  # The products of product_ids, when sent, which must all be products of this AI agent.
  def fetch_products
    ids = params.permit(product_ids: [])[:product_ids]
    return if ids.nil?

    @products = @ai_agent.products.where(id: ids).to_a
    render_could_not_create_error(I18n.t('ai_agents.promotions.errors.unknown_products')) if @products.size != ids.uniq.size
  end

  def promotion_params
    attributes = params.permit(:title, :description, :starts_on, :ends_on)
    @products ? attributes.merge(products: @products) : attributes
  end
end

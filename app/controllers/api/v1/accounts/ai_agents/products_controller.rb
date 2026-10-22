class Api::V1::Accounts::AiAgents::ProductsController < Api::V1::Accounts::AiAgents::BaseController
  before_action :fetch_product, only: [:update, :destroy]

  def index
    @products = @ai_agent.products.with_attached_image.order(id: :desc)
    @products = @products.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%") if params[:q].present?
  end

  def create
    @product = @ai_agent.products.create!(product_params)
  end

  def update
    @product.update!(product_params)
  end

  def destroy
    @product.destroy!
    head :ok
  end

  def bulk_destroy
    @ai_agent.products.where(id: params.require(:ids)).destroy_all
    head :ok
  end

  private

  def fetch_product
    @product = @ai_agent.products.find(params[:id])
  end

  def product_params
    params.permit(:name, :description, :price, :weight, :stock, :image)
  end
end

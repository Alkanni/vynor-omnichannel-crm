# == Schema Information
#
# Table name: ai_agent_promotion_products
#
#  id           :bigint           not null, primary key
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  product_id   :bigint           not null
#  promotion_id :bigint           not null
#
# Indexes
#
#  index_ai_agent_promotion_products_on_product_id  (product_id)
#  index_ai_agent_promotion_products_uniqueness     (promotion_id,product_id) UNIQUE
#
# A product a promotion applies to, a product of the same AI agent.
class AiAgent::PromotionProduct < ApplicationRecord
  belongs_to :promotion, class_name: 'AiAgent::Promotion'
  belongs_to :product, class_name: 'AiAgent::Product'
end

class AddPromotionOffersEnabledToAiAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agents, :promotion_offers_enabled, :boolean, default: false, null: false
  end
end

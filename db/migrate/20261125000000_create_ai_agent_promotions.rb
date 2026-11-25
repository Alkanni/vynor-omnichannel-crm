class CreateAiAgentPromotions < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_promotions do |t|
      t.references :account, null: false, index: true
      t.references :ai_agent, null: false, index: true
      t.string :title, null: false
      t.text :description, null: false
      t.date :starts_on
      t.date :ends_on
      t.timestamps
    end

    create_table :ai_agent_promotion_products do |t|
      t.references :promotion, null: false, index: false
      t.references :product, null: false, index: true
      t.timestamps
    end
    add_index :ai_agent_promotion_products, [:promotion_id, :product_id], unique: true, name: :index_ai_agent_promotion_products_uniqueness
  end
end

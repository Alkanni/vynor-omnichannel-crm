class CreateAiAgentProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_products do |t|
      t.references :account, null: false, index: true
      t.references :ai_agent, null: false, index: true
      t.string :name, null: false
      t.text :description
      t.decimal :price, precision: 15, scale: 2, null: false, default: 0
      t.integer :weight, null: false, default: 0
      t.integer :stock, null: false, default: 0
      t.timestamps
    end
  end
end

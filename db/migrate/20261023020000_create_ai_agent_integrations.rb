class CreateAiAgentIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_integrations do |t|
      t.references :account, null: false, index: true
      t.references :ai_agent, null: false, index: false
      t.string :integration_type, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :settings, null: false, default: {}
      t.text :credentials
      t.timestamps
    end
    add_index :ai_agent_integrations, [:ai_agent_id, :integration_type], unique: true, name: 'index_ai_agent_integrations_on_agent_and_type'
  end
end

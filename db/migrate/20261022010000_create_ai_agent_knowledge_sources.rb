class CreateAiAgentKnowledgeSources < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_knowledge_sources do |t|
      t.references :account, null: false, index: true
      t.references :ai_agent, null: false, index: false
      t.integer :source_type, null: false
      t.string :title, null: false
      t.text :content
      t.timestamps
    end
    add_index :ai_agent_knowledge_sources, [:ai_agent_id, :source_type], name: 'index_ai_agent_knowledge_sources_on_agent_and_type'
  end
end

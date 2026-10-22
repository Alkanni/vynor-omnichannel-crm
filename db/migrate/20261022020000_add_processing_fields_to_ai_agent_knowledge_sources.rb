class AddProcessingFieldsToAiAgentKnowledgeSources < ActiveRecord::Migration[7.1]
  def change
    change_table :ai_agent_knowledge_sources, bulk: true do |t|
      t.text :external_url
      t.integer :status, null: false, default: 0
      t.string :error_message
      t.jsonb :metadata, null: false, default: {}
    end
  end
end

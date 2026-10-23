class CreateAiAgentKnowledgeChunks < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_knowledge_chunks do |t|
      t.references :account, null: false, index: true
      t.references :ai_agent, null: false, index: true
      t.references :chunkable, polymorphic: true, null: false, index: true
      t.datetime :chunkable_updated_at, null: false
      t.text :content, null: false
      t.vector :embedding, limit: 1536, null: false
      t.timestamps
    end
  end
end

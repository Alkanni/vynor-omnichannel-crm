class CreateAiAgentReplyTraces < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_reply_traces do |t|
      t.references :account, null: false, index: false
      t.references :ai_agent, null: false, index: false
      t.references :conversation, null: false, index: true
      t.references :message, null: false, index: false
      t.integer :status, null: false
      t.string :model, null: false
      t.string :retrieval_mode
      t.string :embedding_model
      t.jsonb :retrieved, null: false, default: []
      t.jsonb :labels, null: false, default: []
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :latency_ms
      t.string :error_class
      t.timestamps
    end
    add_index :ai_agent_reply_traces, [:ai_agent_id, :created_at]
  end
end

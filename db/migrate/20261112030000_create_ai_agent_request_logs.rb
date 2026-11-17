class CreateAiAgentRequestLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_request_logs do |t|
      t.references :account, null: false, index: false
      t.references :ai_agent, null: false, index: false
      t.string :source, null: false
      t.references :conversation, index: true
      t.references :message, index: false
      t.references :reply_trace, index: false
      t.string :status, null: false
      t.string :error_class
      t.integer :latency_ms
      t.jsonb :input, null: false, default: {}
      t.jsonb :output, null: false, default: {}
      t.jsonb :steps, null: false, default: []
      t.datetime :created_at, null: false
    end
    add_index :ai_agent_request_logs, :created_at
    add_index :ai_agent_request_logs, [:ai_agent_id, :created_at]
  end
end

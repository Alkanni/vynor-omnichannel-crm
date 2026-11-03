class AddScopeGuardToAiAgents < ActiveRecord::Migration[7.1]
  def change
    change_table :ai_agents, bulk: true do |t|
      t.text :off_topic_message
      t.text :clarification_message
    end
    change_table :ai_agent_reply_traces, bulk: true do |t|
      t.string :scope_decision
      t.integer :scope_latency_ms
    end

    # Strict mode now requires both replies, so strict agents from before the scope check get a default to edit.
    up_only do
      execute <<~SQL.squish
        UPDATE ai_agents
        SET off_topic_message = 'Maaf, saya hanya dapat membantu pertanyaan seputar layanan kami.',
            clarification_message = 'Boleh dijelaskan lebih detail produk atau layanan yang dimaksud?',
            scope_policy_version = scope_policy_version + 1
        WHERE scope_mode = 'strict'
      SQL
    end
  end
end

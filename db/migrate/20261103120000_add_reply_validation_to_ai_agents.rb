class AddReplyValidationToAiAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agents, :knowledge_gap_message, :text
    change_table :ai_agent_reply_traces, bulk: true do |t|
      t.string :reply_decision
      t.jsonb :cited_ranks, null: false, default: []
      t.string :blocked_reason
    end

    # Strict mode now requires the knowledge gap message, so strict agents from before the reply check get a default to edit.
    up_only do
      execute <<~SQL.squish
        UPDATE ai_agents
        SET knowledge_gap_message = 'Maaf, informasi tersebut belum tersedia di kami. Ada hal lain yang bisa kami bantu?',
            scope_policy_version = scope_policy_version + 1
        WHERE scope_mode = 'strict'
      SQL
    end
  end
end

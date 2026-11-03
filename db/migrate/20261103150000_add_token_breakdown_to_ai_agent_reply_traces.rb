class AddTokenBreakdownToAiAgentReplyTraces < ActiveRecord::Migration[7.1]
  def change
    change_table :ai_agent_reply_traces, bulk: true do |t|
      t.integer :scope_input_tokens
      t.integer :scope_output_tokens
      t.integer :cached_input_tokens
      t.integer :watcher_input_tokens
      t.integer :watcher_output_tokens
      t.integer :watcher_cached_input_tokens
    end
  end
end

class AddWebResultsToAiAgentReplyTraces < ActiveRecord::Migration[7.1]
  def change
    change_table :ai_agent_reply_traces, bulk: true do |t|
      t.jsonb :web_results, null: false, default: []
      t.integer :web_latency_ms
      t.decimal :web_cost_usd, precision: 10, scale: 6
    end
  end
end

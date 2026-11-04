class AddWebSearchToAiAgents < ActiveRecord::Migration[7.1]
  def change
    change_table :ai_agents, bulk: true do |t|
      t.boolean :web_search_enabled, null: false, default: false
      t.text :web_search_domains
    end
    add_column :ai_agent_reply_traces, :web_search_status, :string
  end
end

class AddScopePolicyToAiAgents < ActiveRecord::Migration[7.1]
  def change
    change_table :ai_agents, bulk: true do |t|
      t.string :scope_mode, null: false, default: 'off'
      t.text :business_description
      t.text :allowed_topics
      t.text :disallowed_topics
      t.integer :scope_policy_version, null: false, default: 0
    end
    add_column :ai_agent_reply_traces, :scope_policy_version, :integer, null: false, default: 0
  end
end

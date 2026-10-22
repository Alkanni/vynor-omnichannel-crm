class CreateAiAgents < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agents do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.text :behavior, :welcome_message, :transfer_conditions, :label_conditions
      t.string :pending_assigned_message, :pending_unassigned_message
      t.boolean :stop_ai_after_handoff, null: false, default: true
      t.boolean :silent_handoff, :watcher_enabled, :session_only_memory, :ignore_team_handoff, null: false, default: false
      t.jsonb :allowed_label_ids, null: false, default: []
      t.string :model, null: false
      t.string :temperature, null: false, default: 'balanced'
      t.string :timezone, null: false, default: 'Asia/Jakarta'
      t.integer :history_limit, null: false, default: 30
      t.integer :read_file_limit, null: false, default: 3
      t.integer :context_limit, null: false, default: 40
      t.integer :message_await, null: false, default: 10
      t.integer :message_limit, null: false, default: 10
      t.timestamps
    end
  end
end

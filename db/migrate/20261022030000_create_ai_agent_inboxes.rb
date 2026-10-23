class CreateAiAgentInboxes < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_inboxes do |t|
      t.references :ai_agent, null: false, index: true
      t.references :inbox, null: false, index: { unique: true }
      t.timestamps
    end
  end
end

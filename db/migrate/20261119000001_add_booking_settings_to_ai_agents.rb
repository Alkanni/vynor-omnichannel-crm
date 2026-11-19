class AddBookingSettingsToAiAgents < ActiveRecord::Migration[7.1]
  def change
    change_table :ai_agents, bulk: true do |t|
      t.boolean :booking_enabled, null: false, default: false
      t.text :booking_conditions
      t.bigint :booking_label_id
      t.jsonb :booking_fields, null: false, default: []
    end
  end
end

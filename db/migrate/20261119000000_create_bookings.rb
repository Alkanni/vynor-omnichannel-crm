class CreateBookings < ActiveRecord::Migration[7.1]
  def change
    create_table :bookings do |t|
      t.references :account, null: false, index: false
      t.references :conversation, null: false
      t.references :contact, null: false
      t.references :ai_agent
      t.integer :status, null: false, default: 0
      t.datetime :scheduled_at, null: false
      t.string :service, null: false
      t.string :customer_name, null: false
      t.text :notes
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :bookings, [:account_id, :scheduled_at]
    add_index :bookings, [:account_id, :status]
  end
end

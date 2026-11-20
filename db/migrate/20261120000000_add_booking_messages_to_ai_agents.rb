class AddBookingMessagesToAiAgents < ActiveRecord::Migration[7.1]
  def change
    change_table :ai_agents, bulk: true do |t|
      t.text :booking_confirmed_message
      t.text :booking_cancelled_message
    end
  end
end

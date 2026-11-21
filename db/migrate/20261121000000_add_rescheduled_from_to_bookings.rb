class AddRescheduledFromToBookings < ActiveRecord::Migration[7.1]
  def change
    add_reference :bookings, :rescheduled_from, index: true
  end
end

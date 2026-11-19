json.payload @bookings do |booking|
  json.partial! 'api/v1/models/booking', formats: [:json], booking: booking
end

json.meta do
  json.count @bookings.total_count
  json.current_page @bookings.current_page
end

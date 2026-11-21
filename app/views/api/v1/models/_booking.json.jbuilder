json.id booking.id
json.status booking.status
# The statuses staff may change it to (see Booking::NEXT_STATUSES).
json.next_statuses booking.next_statuses
json.scheduled_at booking.scheduled_at.iso8601
json.service booking.service
json.customer_name booking.customer_name
json.notes booking.notes
json.details booking.details
json.contact do
  json.id booking.contact.id
  json.name booking.contact.name
  json.phone_number booking.contact.phone_number
end
json.conversation do
  json.id booking.conversation.id
  json.display_id booking.conversation.display_id
  json.inbox_id booking.conversation.inbox_id
end
if booking.ai_agent
  json.ai_agent do
    json.id booking.ai_agent.id
    json.name booking.ai_agent.name
  end
else
  json.ai_agent nil
end
json.created_at booking.created_at.iso8601

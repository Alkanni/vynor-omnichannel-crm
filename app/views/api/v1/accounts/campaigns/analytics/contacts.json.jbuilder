json.payload @recipients do |recipient|
  json.id recipient.id
  json.status recipient.status
  json.message_content recipient.message_content
  json.error_code recipient.error_code
  json.error_title recipient.error_title
  json.error_message recipient.error_message
  json.contact do
    json.id recipient.contact.id
    json.name recipient.contact.name
    json.phone_number recipient.contact.phone_number
  end
end

json.meta do
  json.total_count @recipients.total_count
  json.current_page @recipients.current_page
end

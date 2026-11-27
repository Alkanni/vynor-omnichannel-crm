# Who recorded or changed the booking, when, and each field's value before (none for the recorded booking) and after,
# in Booking::HISTORY_FIELDS order. Where a change came from (remote_address, request_uuid) stays out.
json.payload @audits do |audit|
  json.id audit.id
  json.action audit.action
  if audit.user_type
    json.actor do
      json.type audit.user_type
      json.id audit.user_id
      # None once the user or AI agent is deleted.
      json.name audit.user&.name
    end
  else
    json.actor nil
  end
  json.changes(Booking::HISTORY_FIELDS & audit.audited_changes.keys) do |field|
    json.field field
    json.from audit.action == 'update' ? audit.old_attributes[field] : nil
    json.to audit.new_attributes[field]
  end
  json.comment audit.comment
  json.created_at audit.created_at.iso8601
end

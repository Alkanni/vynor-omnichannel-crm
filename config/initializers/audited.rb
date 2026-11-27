# configuration related audited gem : https://github.com/collectiveidea/audited

Audited.config do |config|
  # A booking's history (see Booking::HISTORY_FIELDS) keeps its statuses by name, as the bookings API returns them.
  config.store_synthesized_enums = true
end

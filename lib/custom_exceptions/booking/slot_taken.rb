# frozen_string_literal: true

# A booking would take the slot of a confirmed booking (see Booking#take_slot!). The message names that booking by its id,
# service, and time only, since the user may not be allowed to open its conversation; error_code tells the dashboard to
# show it as a warning instead of the generic error.
class CustomExceptions::Booking::SlotTaken < CustomExceptions::Base
  def message
    I18n.t('bookings.errors.slot_taken', id: @data.id, service: @data.service, scheduled_at: @data.local_time(@data.scheduled_at))
  end

  def to_hash
    { message: message, error_code: 'booking_slot_taken' }
  end

  def http_status
    422
  end
end

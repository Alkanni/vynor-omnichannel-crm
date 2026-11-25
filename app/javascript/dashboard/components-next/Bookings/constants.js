// The statuses of a booking, in the order staff move it through (see Booking#status).
export const BOOKING_STATUSES = Object.freeze([
  'requested',
  'confirmed',
  'cancelled',
  'completed',
  'no_show',
  'rescheduled',
]);

// The status a booking never leaves (see Booking::NEXT_STATUSES), which staff confirm before choosing it.
export const BOOKING_FINAL_STATUS = 'cancelled';

export const BOOKING_STATUS_LABELS = Object.freeze({
  requested: 'BOOKINGS.STATUS.REQUESTED',
  confirmed: 'BOOKINGS.STATUS.CONFIRMED',
  cancelled: 'BOOKINGS.STATUS.CANCELLED',
  completed: 'BOOKINGS.STATUS.COMPLETED',
  no_show: 'BOOKINGS.STATUS.NO_SHOW',
  rescheduled: 'BOOKINGS.STATUS.RESCHEDULED',
});

export const BOOKING_STATUS_CLASSES = Object.freeze({
  requested: 'bg-n-amber-3 text-n-amber-11',
  confirmed: 'bg-n-teal-3 text-n-teal-11',
  cancelled: 'bg-n-slate-3 text-n-slate-11',
  completed: 'bg-n-blue-3 text-n-blue-11',
  no_show: 'bg-n-ruby-3 text-n-ruby-11',
  rescheduled: 'bg-n-iris-3 text-n-iris-11',
});

// The error_code of the 422 the bookings API returns when a confirmed booking holds the slot already (see
// CustomExceptions::Booking::SlotTaken); its message names that booking.
export const BOOKING_SLOT_TAKEN_ERROR = 'booking_slot_taken';

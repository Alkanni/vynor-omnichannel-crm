import { BOOKING_SLOT_TAKEN_ERROR } from './constants';

// A booking time in the viewer's time zone, e.g. "Fri, 20 Nov 2026, 10:00".
export const formatBookingTime = (time, locale) =>
  new Intl.DateTimeFormat(locale, {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(time));

// The route of the conversation a booking was recorded in.
export const bookingConversationRoute = (accountId, booking) => ({
  name: 'inbox_conversation',
  params: { accountId, conversation_id: booking.conversation.display_id },
});

// Upcoming bookings first, soonest first, then past ones, latest first.
export const sortUpcomingFirst = (bookings, now = Date.now()) => {
  const at = booking => new Date(booking.scheduled_at).getTime();
  const upcoming = bookings.filter(booking => at(booking) >= now);
  const past = bookings.filter(booking => at(booking) < now);
  return [
    ...upcoming.sort((a, b) => at(a) - at(b)),
    ...past.sort((a, b) => at(b) - at(a)),
  ];
};

const pad = number => String(number).padStart(2, '0');

// A date as the YYYY-MM-DD value of a date input, in the viewer's time zone.
export const localDate = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;

// A time as the HH:MM value of a time input, in the viewer's time zone.
export const localTime = date =>
  `${pad(date.getHours())}:${pad(date.getMinutes())}`;

// A YYYY-MM-DD day and an HH:MM time in the viewer's time zone, as an ISO 8601 time for the bookings API.
export const localDateTime = (day, time) => {
  const [year, month, date] = day.split('-').map(Number);
  const [hours, minutes] = time.split(':').map(Number);
  return new Date(year, month - 1, date, hours, minutes).toISOString();
};

// The start of a YYYY-MM-DD day in the viewer's time zone, `addDays` later, as an ISO 8601 time for the bookings API.
export const startOfLocalDay = (day, addDays = 0) => {
  const [year, month, date] = day.split('-').map(Number);
  return new Date(year, month - 1, date + addDays).toISOString();
};

// The message of a bookings API error refusing a slot a confirmed booking holds, else null.
export const slotTakenMessage = error => {
  const data = error?.response?.data;
  return data?.error_code === BOOKING_SLOT_TAKEN_ERROR ? data.message : null;
};

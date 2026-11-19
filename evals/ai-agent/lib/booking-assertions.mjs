// The booking assertions of promptfooconfig.booking.yaml, over the `booking` metadata of provider.mjs (what a live reply
// would request, see AiAgents::ActionSchema#parse) and the `booking` metadata of each case in tests/b-booking.yaml: null
// for a case that must not request a booking, else what it must request. Dates are relative to when the case runs, in
// the agent's time zone, so a case reads "besok" the way the agent does.
const ZONE = 'Asia/Jakarta';
const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_DAYS = 7;

function inZone(date) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone: ZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
      weekday: 'long',
    })
      .formatToParts(date)
      .map(({ type, value }) => [type, value])
  );
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    time: `${parts.hour}:${parts.minute}`,
    weekday: parts.weekday,
  };
}

// `days` after today, or the first `weekday` (e.g. "Saturday") after today.
function expectedDate({ days, weekday }) {
  if (days != null) return inZone(new Date(Date.now() + days * DAY_MS)).date;

  for (let offset = 1; offset <= WEEK_DAYS; offset += 1) {
    const day = inZone(new Date(Date.now() + offset * DAY_MS));
    if (day.weekday === weekday) return day.date;
  }
  throw new Error(`Unknown weekday ${weekday}`);
}

const includes = (value, part) =>
  String(value || '')
    .toLowerCase()
    .includes(part.toLowerCase());

// A booking is requested exactly when the case expects one.
export function requestedAsExpected(_output, { metadata, test }) {
  const expected = test.metadata.booking != null;
  const requested = metadata.booking != null;
  return {
    pass: expected === requested,
    score: expected === requested ? 1 : 0,
    reason: requested
      ? `requested ${JSON.stringify(metadata.booking)}`
      : 'no booking requested',
  };
}

// The requested booking is on the expected date and time; passes when either side has no booking, which
// requestedAsExpected grades.
export function onExpectedTime(_output, { metadata, test }) {
  const expected = test.metadata.booking;
  if (!expected || !metadata.booking) return true;

  const at = inZone(new Date(metadata.booking.scheduled_at));
  const want = { date: expectedDate(expected), time: expected.time };
  const pass = at.date === want.date && at.time === want.time;
  return {
    pass,
    score: pass ? 1 : 0,
    reason: `got ${at.date} ${at.time}, expected ${want.date} ${want.time}`,
  };
}

// The requested booking names the expected service and customer, and has the expected notes and agent fields, each as
// a part of its value, case aside.
export function withExpectedFields(_output, { metadata, test }) {
  const expected = test.metadata.booking;
  if (!expected || !metadata.booking) return true;

  const { service, customer_name: name, notes, details } = metadata.booking;
  const wrong = [
    !includes(service, expected.service) && `service "${service}"`,
    !includes(name, expected.name) && `customer_name "${name}"`,
    expected.notes && !includes(notes, expected.notes) && `notes "${notes}"`,
    ...Object.entries(expected.details || {}).map(
      ([field, part]) =>
        !includes(details?.[field], part) && `${field} "${details?.[field]}"`
    ),
  ].filter(Boolean);
  return {
    pass: wrong.length === 0,
    score: wrong.length === 0 ? 1 : 0,
    reason: wrong.length ? `unexpected ${wrong.join(', ')}` : 'fields match',
  };
}

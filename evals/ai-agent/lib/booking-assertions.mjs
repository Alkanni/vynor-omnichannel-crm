// The booking assertions of promptfooconfig.booking.yaml, over the `booking` metadata of provider.mjs (what a live reply
// would request, see AiAgents::ActionSchema#parse) and the `booking` metadata of each case in tests/b-booking.yaml: null
// for a case that must not request a booking, else what it must request. The summary assertions of
// promptfooconfig.booking-summary.yaml (issue #206) do the same over the `bookingSummary` metadata (the summary bubble a
// live reply of an agent with a summary template ends with) and the `summary` metadata of a case, in the shape of
// `booking`; a case without it must show none. The assertions of promptfooconfig.booking-fields.yaml (issue #207) add the
// `exact` values of `booking` and the `asks` words of a case. Dates are relative to when the case runs, in the agent's
// time zone, so a case reads "besok" the way the agent does.
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

// A summary is shown exactly when the case expects one.
export function summaryAsExpected(_output, { metadata, test }) {
  const expected = test.metadata.summary != null;
  const shown = metadata.bookingSummary != null;
  const rejection = metadata.bookingSummaryRejection;
  return {
    pass: expected === shown,
    score: expected === shown ? 1 : 0,
    reason: shown
      ? `showed ${JSON.stringify(metadata.bookingSummary)}`
      : `no summary${rejection ? ` (${rejection})` : ''}`,
  };
}

// The summary shows the expected date as the template renders it (DD/MM/YYYY), the time, and a part of the service, the
// customer name, the notes, and the agent fields, case aside; passes when either side has no summary.
export function summaryWithExpectedValues(_output, { metadata, test }) {
  const expected = test.metadata.summary;
  const summary = metadata.bookingSummary;
  if (!expected || !summary) return true;

  const [year, month, day] = expectedDate(expected).split('-');
  const missing = [
    `${day}/${month}/${year}`,
    expected.time,
    expected.service,
    expected.name,
    expected.notes,
    ...Object.values(expected.details || {}),
  ].filter(part => part && !includes(summary, part));
  return {
    pass: missing.length === 0,
    score: missing.length === 0 ? 1 : 0,
    reason: missing.length ? `missing ${missing.join(', ')}` : 'values match',
  };
}

// The model leaves the summary to the template: none of its own bubbles before the summary names the service.
export function summaryNotRepeated(_output, { metadata, test }) {
  const expected = test.metadata.summary;
  if (!expected || !metadata.bookingSummary) return true;

  const repeated = (metadata.messages || [])
    .slice(0, -1)
    .filter(bubble => includes(bubble, expected.service));
  return {
    pass: repeated.length === 0,
    score: repeated.length === 0 ? 1 : 0,
    reason: repeated.length
      ? `the model also wrote ${JSON.stringify(repeated)}`
      : 'summary only from the template',
  };
}

// The requested booking holds the `exact` values as written: the service and the agent fields named there; passes when
// either side has no booking.
export function withExactValues(_output, { metadata, test }) {
  const exact = test.metadata.booking?.exact;
  if (!exact || !metadata.booking) return true;

  const wrong = Object.entries(exact)
    .map(([field, value]) => [
      field,
      field === 'service'
        ? metadata.booking.service
        : metadata.booking.details?.[field],
      value,
    ])
    .filter(([, got, value]) => got !== value)
    .map(([field, got]) => `${field} "${got}"`);
  return {
    pass: wrong.length === 0,
    score: wrong.length === 0 ? 1 : 0,
    reason: wrong.length ? `unexpected ${wrong.join(', ')}` : 'values exact',
  };
}

// A reply that must ask for a required field uses one of the `asks` words.
export function asksAsExpected(output, { test }) {
  const words = test.metadata.asks;
  if (!words) return true;

  const pass = words.some(word => includes(output, word));
  return {
    pass,
    score: pass ? 1 : 0,
    reason: pass ? 'asks for the field' : `none of ${words.join(', ')}`,
  };
}

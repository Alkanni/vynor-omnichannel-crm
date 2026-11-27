// Summarizes promptfoo JSON outputs of promptfooconfig.booking.yaml as Markdown: the booking gate of issue #177 per run,
// then every case that failed an assertion with the booking it requested. A run of promptfooconfig.booking-summary.yaml
// also gets the summary gate of issue #206 and the summary of each failing case, and a run of
// promptfooconfig.booking-fields.yaml the structured field rows of issue #207.
// Usage: node booking-report.mjs output/booking-1.json [output/booking-2.json ...]
import { readFileSync } from 'node:fs';

// promptfoo's failureReason: 2 = the provider or the grader errored.
const FAILURE_REASON_ERROR = 2;

function loadRun(file) {
  const { results } = JSON.parse(readFileSync(file, 'utf8'));
  return results.results.map(result => ({
    id: result.testCase.metadata.id,
    expected: result.testCase.metadata.booking,
    requested: result.response?.metadata?.booking ?? null,
    rejection: result.response?.metadata?.bookingRejection ?? null,
    asks: result.testCase.metadata.asks ?? null,
    summaryExpected: result.testCase.metadata.summary ?? null,
    summary: result.response?.metadata?.bookingSummary ?? null,
    summaryRejection:
      result.response?.metadata?.bookingSummaryRejection ?? null,
    blockedReason: result.response?.metadata?.blockedReason,
    output: result.response?.output,
    error: result.failureReason === FAILURE_REASON_ERROR ? result.error : null,
    checks: Object.fromEntries(
      (result.gradingResult?.componentResults || []).map(
        ({ assertion, pass, reason }) => [assertion?.metric, { pass, reason }]
      )
    ),
  }));
}

const percent = (part, whole) =>
  whole ? `${Math.round((part / whole) * 100)}% (${part}/${whole})` : 'n/a';

// Issue #207: a reply asks for a missing required field before the summary, and a booking holds the listed service and
// the option the customer described in other words.
function fieldsGate(valid, created) {
  const asking = valid.filter(testCase => testCase.asks);
  const asked = asking.filter(testCase => testCase.checks.asks_required?.pass);
  const withExact = created.filter(testCase => testCase.expected.exact);
  const exact = withExact.filter(
    testCase => testCase.checks.booking_exact?.pass
  );
  return [
    [
      'Cases that ask for a missing required field',
      percent(asked.length, asking.length),
      '—',
      null,
    ],
    [
      'Bookings with the exact service and options',
      percent(exact.length, withExact.length),
      '—',
      null,
    ],
  ];
}

// Issue #206: a summary exactly on the cases that expect one, with their values, and never also written by the model.
function summaryGate(valid) {
  const expecting = valid.filter(testCase => testCase.summaryExpected != null);
  const others = valid.filter(testCase => testCase.summaryExpected == null);
  const shown = expecting.filter(testCase => testCase.summary);
  const unexpected = others.filter(testCase => testCase.summary);
  const withValues = shown.filter(
    testCase => testCase.checks.summary_values?.pass
  );
  const repeated = shown.filter(
    testCase => testCase.checks.summary_not_repeated?.pass === false
  );
  const rejections = valid
    .filter(testCase => testCase.summaryRejection)
    .map(testCase => `${testCase.id} (${testCase.summaryRejection})`);
  return [
    [
      'Summary on a case that expects none',
      percent(unexpected.length, others.length),
      '0',
      unexpected.length === 0,
    ],
    [
      'Cases expecting a summary with one',
      percent(shown.length, expecting.length),
      '≥ 90%',
      shown.length >= 0.9 * expecting.length,
    ],
    [
      'Summary with the expected values',
      percent(withValues.length, shown.length),
      '100%',
      withValues.length === shown.length,
    ],
    [
      'Summary also written by the model',
      String(repeated.length),
      '0',
      repeated.length === 0,
    ],
    [
      'Summary rejections (report only)',
      [rejections.length, ...rejections].join(' '),
      '—',
      null,
    ],
  ];
}

function gate(cases) {
  const valid = cases.filter(testCase => !testCase.error);
  const negatives = valid.filter(testCase => testCase.expected == null);
  const positives = valid.filter(testCase => testCase.expected != null);
  const created = positives.filter(testCase => testCase.requested);
  const falseBookings = negatives.filter(testCase => testCase.requested);
  // A live reply turns a rejection into an activity message for the staff (issue #189).
  const rejections = valid
    .filter(testCase => testCase.rejection)
    .map(testCase => `${testCase.id} (${testCase.rejection})`);
  const onTime = created.filter(
    testCase => testCase.checks.booking_datetime?.pass
  );
  const fields = created.filter(
    testCase => testCase.checks.booking_fields?.pass
  );
  const blocked = valid.filter(
    testCase => testCase.blockedReason === 'unsupported_number'
  );
  return [
    [
      'Booking on a negative case',
      percent(falseBookings.length, negatives.length),
      '0',
      falseBookings.length === 0,
    ],
    [
      'Positive cases with a booking',
      percent(created.length, positives.length),
      '≥ 90%',
      created.length >= 0.9 * positives.length,
    ],
    [
      'Date and time exact',
      percent(onTime.length, created.length),
      '100%',
      onTime.length === created.length,
    ],
    [
      'Replies blocked as unsupported_number',
      String(blocked.length),
      '0',
      blocked.length === 0,
    ],
    [
      'Booking rejections (report only)',
      [rejections.length, ...rejections].join(' '),
      '—',
      null,
    ],
    [
      'Fields as expected (report only)',
      percent(fields.length, created.length),
      '—',
      null,
    ],
    ...(valid.some(testCase => testCase.checks.summary_shown)
      ? summaryGate(valid)
      : []),
    ...(valid.some(testCase => testCase.checks.booking_exact)
      ? fieldsGate(valid, created)
      : []),
    [
      'Errored cases (left out)',
      String(cases.length - valid.length),
      '—',
      null,
    ],
  ];
}

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('Usage: node booking-report.mjs output/booking-1.json [...]');
  process.exit(1);
}

const lines = [];
for (const file of files) {
  const cases = loadRun(file);
  lines.push(`## ${file}`, '', '| Metric | Result | Target | Met |');
  lines.push('| --- | --- | --- | --- |');
  for (const [name, result, target, met] of gate(cases)) {
    lines.push(
      `| ${name} | ${result} | ${target} | ${met == null ? '' : met ? 'yes' : 'no'} |`
    );
  }
  const failing = cases.filter(
    testCase =>
      testCase.error ||
      Object.values(testCase.checks).some(check => !check.pass)
  );
  lines.push('', `Failing cases: ${failing.length}`, '');
  for (const testCase of failing) {
    const reasons = Object.entries(testCase.checks)
      .filter(([, check]) => !check.pass)
      .map(([metric, check]) => `${metric}: ${check.reason}`);
    lines.push(
      `- ${testCase.id}: ${testCase.error || reasons.join('; ')}`,
      `  - requested: ${JSON.stringify(testCase.requested)}`,
      ...(testCase.summary
        ? [`  - summary: ${testCase.summary.replace(/\s+/g, ' ')}`]
        : []),
      `  - reply: ${String(testCase.output || '').replace(/\s+/g, ' ')}`
    );
  }
  lines.push('');
}
console.log(lines.join('\n'));

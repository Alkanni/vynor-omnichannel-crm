// Summarizes promptfoo JSON outputs of promptfooconfig.booking.yaml as Markdown: the booking gate of issue #177 per run,
// then every case that failed an assertion with the booking it requested.
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

function gate(cases) {
  const valid = cases.filter(testCase => !testCase.error);
  const negatives = valid.filter(testCase => testCase.expected == null);
  const positives = valid.filter(testCase => testCase.expected != null);
  const created = positives.filter(testCase => testCase.requested);
  const falseBookings = negatives.filter(testCase => testCase.requested);
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
      'Fields as expected (report only)',
      percent(fields.length, created.length),
      '—',
      null,
    ],
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
      `  - reply: ${String(testCase.output || '').replace(/\s+/g, ' ')}`
    );
  }
  lines.push('');
}
console.log(lines.join('\n'));

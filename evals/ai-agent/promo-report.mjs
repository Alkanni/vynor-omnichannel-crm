// Summarizes promptfoo JSON outputs of promptfooconfig.promo.yaml as Markdown: the gate of issues #215 and #223 per provider
// over all the runs given, then every case that failed an assertion. Runs of the same config on main after --baseline give
// the rate of replies the reply check blocked, which the runs before it may not exceed. The session limits come from the
// live probe (promo_probe.rb), not from here.
// Usage: node promo-report.mjs output/promo-1.json [...] [--baseline output/promo-main-1.json ...]
import { readFileSync } from 'node:fs';

// promptfoo's failureReason: 2 = the provider or the grader errored.
const FAILURE_REASON_ERROR = 2;

function loadRun(file) {
  const { results } = JSON.parse(readFileSync(file, 'utf8'));
  return results.results.map(result => ({
    file,
    provider: result.provider?.label || result.provider?.id,
    id: result.testCase.metadata.id,
    category: result.testCase.metadata.category,
    promotion: result.response?.metadata?.promotion ?? null,
    blockedReason: result.response?.metadata?.blockedReason ?? null,
    output: result.response?.output ?? '',
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
const rate = (part, whole) => (whole ? part / whole : 0);
const failed = (testCase, metric) => testCase.checks[metric]?.pass === false;

function gate(cases, baseline) {
  const valid = cases.filter(testCase => !testCase.error);
  const inCategory = category =>
    valid.filter(testCase => testCase.category === category);
  const relevant = inCategory('relevant');
  const offered = relevant.filter(
    testCase => !failed(testCase, 'promotion_mentioned')
  );
  const irrelevant = inCategory('irrelevant');
  const spam = irrelevant.filter(testCase =>
    failed(testCase, 'promotion_mentioned')
  );
  // An irrelevant case whose prompt had the offer block, whether or not the reply used it (#223).
  const irrelevantOffers = irrelevant.filter(
    testCase => testCase.promotion?.placement === 'offer'
  );
  const complaints = inCategory('complaint');
  const complaintOffers = complaints.filter(testCase =>
    failed(testCase, 'promotion_mentioned')
  );
  const direct = inCategory('direct');
  const directRight = direct.filter(
    testCase => !failed(testCase, 'promotion_mentioned')
  );
  const inactive = valid.filter(testCase =>
    failed(testCase, 'no_inactive_promotion')
  );
  const many = valid.filter(testCase => failed(testCase, 'one_promotion'));
  const blocked = valid.filter(testCase => testCase.blockedReason);
  const baselineValid = baseline.filter(testCase => !testCase.error);
  const baselineBlocked = baselineValid.filter(
    testCase => testCase.blockedReason
  );
  return [
    [
      'Relevant cases that mention their promotion',
      percent(offered.length, relevant.length),
      '≥ 80%',
      offered.length >= 0.8 * relevant.length,
    ],
    [
      'Irrelevant cases that mention a promotion (spam)',
      percent(spam.length, irrelevant.length),
      '≤ 5%',
      spam.length <= 0.05 * irrelevant.length,
    ],
    [
      'Irrelevant cases with an offer in the prompt (#223)',
      `${percent(irrelevantOffers.length, irrelevant.length)}${irrelevantOffers.length ? `: ${[...new Set(irrelevantOffers.map(testCase => testCase.id))].join(', ')}` : ''}`,
      '0',
      irrelevantOffers.length === 0,
    ],
    [
      'Replies with a scheduled or archived promotion',
      String(inactive.length),
      '0',
      inactive.length === 0,
    ],
    [
      'Prompts with more than one promotion',
      String(many.length),
      '0',
      many.length === 0,
    ],
    [
      'Offers on a complaint or a request for staff',
      percent(complaintOffers.length, complaints.length),
      '≤ 5%',
      complaintOffers.length <= 0.05 * complaints.length,
    ],
    [
      'Replies the reply check blocked',
      `${percent(blocked.length, valid.length)} vs main ${percent(baselineBlocked.length, baselineValid.length)}`,
      'not above main',
      baselineValid.length
        ? rate(blocked.length, valid.length) <=
          rate(baselineBlocked.length, baselineValid.length)
        : null,
    ],
    [
      'Direct questions answered with the right promotion (report only)',
      percent(directRight.length, direct.length),
      '—',
      null,
    ],
    ['Errors (left out above)', String(cases.length - valid.length), '—', null],
  ];
}

const status = pass => {
  if (pass == null) return '—';
  return pass ? 'PASS' : 'FAIL';
};

const args = process.argv.slice(2);
const split = args.indexOf('--baseline');
const runFiles = split === -1 ? args : args.slice(0, split);
const baselineFiles = split === -1 ? [] : args.slice(split + 1);
if (runFiles.length === 0) {
  console.error(
    'Usage: node promo-report.mjs output/promo-1.json [...] [--baseline output/promo-main-1.json ...]'
  );
  process.exit(1);
}

const cases = runFiles.flatMap(loadRun);
const baseline = baselineFiles.flatMap(loadRun);
const providers = [...new Set(cases.map(testCase => testCase.provider))];
console.log(
  `# Promotion eval: ${runFiles.join(', ')}${baselineFiles.length ? `; baseline ${baselineFiles.join(', ')}` : ''}\n`
);
providers.forEach(provider => {
  console.log(`## ${provider}\n`);
  console.log('| Metric | Result | Target | Status |\n|---|---|---|---|');
  gate(
    cases.filter(testCase => testCase.provider === provider),
    baseline.filter(testCase => testCase.provider === provider)
  ).forEach(([metric, result, target, pass]) =>
    console.log(`| ${metric} | ${result} | ${target} | ${status(pass)} |`)
  );
  console.log();
});

const failures = cases.filter(
  testCase =>
    testCase.error ||
    Object.values(testCase.checks).some(check => check.pass === false)
);
console.log(`## Failing cases (${failures.length})\n`);
console.log('| Run | Provider | Case | Why | Reply |\n|---|---|---|---|---|');
failures.forEach(testCase => {
  const why =
    testCase.error ||
    Object.entries(testCase.checks)
      .filter(([, check]) => check.pass === false)
      .map(([metric, check]) => `${metric}: ${check.reason}`)
      .join('; ');
  const reply = testCase.output.replace(/\s+/g, ' ').slice(0, 160);
  console.log(
    `| ${testCase.file} | ${testCase.provider} | ${testCase.id} | ${why} | ${reply} |`
  );
});

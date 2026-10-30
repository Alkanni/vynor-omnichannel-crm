// Summarizes promptfoo JSON outputs as Markdown: pass rate per category, agent tokens and latency, failing cases and,
// given two runs, the cases whose result changed between them (flaky candidates).
// Usage: node report.mjs output/run-1.json [output/run-2.json]
import { readFileSync } from 'node:fs';

const REASON_LENGTH = 160;
// promptfoo's failureReason: 1 = an assertion failed, 2 = the provider or the grader errored.
const FAILURE_REASON_ERROR = 2;

function loadRun(file) {
  const { results } = JSON.parse(readFileSync(file, 'utf8'));
  return results.results.map(result => ({
    id: result.testCase.metadata.id,
    category: result.testCase.metadata.category,
    flaky: Boolean(result.testCase.metadata.flaky),
    pass: result.success,
    error: result.failureReason === FAILURE_REASON_ERROR ? result.error : null,
    reasons: (result.gradingResult?.componentResults || [])
      .filter(component => !component.pass)
      .map(component => component.reason),
    inputTokens: result.response?.tokenUsage?.prompt,
    outputTokens: result.response?.tokenUsage?.completion,
    agentLatencyMs: result.response?.metadata?.agentLatencyMs,
  }));
}

function stats(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (sorted.length === 0) return 'n/a';

  const average = Math.round(
    sorted.reduce((sum, value) => sum + value, 0) / sorted.length
  );
  return `avg ${average}, p50 ${sorted[Math.floor(sorted.length / 2)]}, max ${sorted[sorted.length - 1]} (n=${sorted.length})`;
}

function report(file, cases) {
  const lines = [
    `### ${file}`,
    '',
    '| Kategori | Lulus | Gagal | Error | Pass rate |',
    '|---|---|---|---|---|',
  ];
  const categories = [
    ...new Set(cases.map(testCase => testCase.category)),
  ].sort();
  for (const category of [...categories, 'Total']) {
    const scope =
      category === 'Total'
        ? cases
        : cases.filter(testCase => testCase.category === category);
    const passed = scope.filter(testCase => testCase.pass).length;
    const errors = scope.filter(testCase => testCase.error).length;
    const rate = `${Math.round((passed / scope.length) * 100)}%`;
    lines.push(
      `| ${category} | ${passed} | ${scope.length - passed - errors} | ${errors} | ${rate} (${passed}/${scope.length}) |`
    );
  }
  lines.push(
    '',
    `- Input tokens per balasan: ${stats(cases.map(testCase => testCase.inputTokens))}`,
    `- Output tokens per balasan: ${stats(cases.map(testCase => testCase.outputTokens))}`,
    `- Latency agent (ms, retrieval + model): ${stats(cases.map(testCase => testCase.agentLatencyMs))}`,
    '',
    'Kasus tidak lulus:'
  );
  const failing = cases.filter(candidate => !candidate.pass);
  for (const testCase of failing) {
    const reason = (testCase.error || testCase.reasons.join(' | '))
      .replace(/\s+/g, ' ')
      .slice(0, REASON_LENGTH);
    lines.push(
      `- ${testCase.id}${testCase.flaky ? ' (flaky)' : ''}: ${reason}`
    );
  }
  if (failing.length === 0) lines.push('- tidak ada');
  return lines.join('\n');
}

const files = process.argv.slice(2);
if (files.length === 0 || files.length > 2) {
  console.error('Usage: node report.mjs output/run-1.json [output/run-2.json]');
  process.exit(1);
}

const runs = files.map(loadRun);
console.log(files.map((file, index) => report(file, runs[index])).join('\n\n'));

if (runs.length === 2) {
  const second = new Map(runs[1].map(testCase => [testCase.id, testCase]));
  const changed = runs[0].filter(
    testCase =>
      second.has(testCase.id) && second.get(testCase.id).pass !== testCase.pass
  );
  console.log('\n### Hasil berbeda antar-run (kandidat flaky)\n');
  console.log(
    changed.length
      ? changed
          .map(
            testCase =>
              `- ${testCase.id}: run 1 ${testCase.pass ? 'lulus' : 'gagal'}, run 2 ${testCase.pass ? 'gagal' : 'lulus'}`
          )
          .join('\n')
      : '- tidak ada'
  );
}

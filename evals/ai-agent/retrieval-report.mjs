// Summarizes retrieval eval outputs as Markdown: hit@1, hit@5 and MRR per category, chunks retrieved, the score
// distribution of relevant vs irrelevant chunks (for choosing a relevance threshold), and, given two runs, the cases
// whose hit@5 result changed.
// Usage: node retrieval-report.mjs output/retrieval-vector.json [output/retrieval-keyword.json]
import { readFileSync } from 'node:fs';
import {
  expectedTitles,
  firstExpectedRank,
  HIT_RANK,
} from './lib/retrieval.mjs';

const NO_ANSWER = 'tanpa-jawaban';

function loadRun(file) {
  const { results } = JSON.parse(readFileSync(file, 'utf8'));
  return results.results.map(result => {
    const hits = result.response?.metadata?.hits || [];
    const expected = expectedTitles(result.testCase.vars);
    const relevant = hits.filter(hit => expected.includes(hit.title));
    const irrelevant = hits.filter(hit => !expected.includes(hit.title));
    return {
      id: result.testCase.metadata.id,
      category: result.testCase.metadata.category,
      mode: result.response?.metadata?.mode,
      embeddingModel: result.response?.metadata?.embeddingModel,
      error: result.response?.error,
      pass: result.success,
      answerable: expected.length > 0,
      rank: firstExpectedRank(hits, expected),
      retrieved: hits.length,
      bestRelevant: relevant[0]?.score,
      bestIrrelevant: irrelevant[0]?.score,
    };
  });
}

function round(value) {
  return Number.isInteger(value) ? value : Number(value.toFixed(4));
}

function stats(values) {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (sorted.length === 0) return 'n/a';

  const middle = sorted[Math.floor(sorted.length / 2)];
  return `min ${round(sorted[0])}, p50 ${round(middle)}, max ${round(sorted[sorted.length - 1])} (n=${sorted.length})`;
}

function percent(part, total) {
  return total ? `${Math.round((part / total) * 100)}%` : 'n/a';
}

function report(file, cases) {
  const { mode, embeddingModel } = cases.find(testCase => testCase.mode) || {};
  const lines = [
    `### ${file}`,
    '',
    `Mode: \`${mode}\`${embeddingModel ? ` (\`${embeddingModel}\`)` : ''}. Kasus tanpa error: ${cases.length}.`,
    '',
    `| Kategori | n | hit@1 | hit@${HIT_RANK} | MRR | Chunks diambil (rata-rata) |`,
    '|---|---|---|---|---|---|',
  ];
  const answerable = cases.filter(testCase => testCase.answerable);
  const categories = [
    ...new Set(answerable.map(testCase => testCase.category)),
  ];
  for (const category of [...categories, 'Total']) {
    const scope =
      category === 'Total'
        ? answerable
        : answerable.filter(testCase => testCase.category === category);
    const hitAt = rank =>
      scope.filter(testCase => testCase.rank && testCase.rank <= rank).length;
    const mrr =
      scope.reduce(
        (sum, testCase) => sum + (testCase.rank ? 1 / testCase.rank : 0),
        0
      ) / scope.length;
    const retrieved =
      scope.reduce((sum, testCase) => sum + testCase.retrieved, 0) /
      scope.length;
    lines.push(
      `| ${category} | ${scope.length} | ${percent(hitAt(1), scope.length)} | ${percent(hitAt(HIT_RANK), scope.length)} | ${mrr.toFixed(2)} | ${retrieved.toFixed(1)} |`
    );
  }

  const noAnswer = cases.filter(testCase => testCase.category === NO_ANSWER);
  lines.push(
    '',
    `Tanpa jawaban: ${noAnswer.filter(testCase => testCase.retrieved === 0).length}/${noAnswer.length} tidak mengambil chunk apa pun.`,
    '',
    `Sebaran skor (${mode === 'vector' ? 'cosine distance, makin kecil makin dekat' : 'skor, makin besar makin dekat'}):`,
    `- Chunk relevan terbaik per kasus: ${stats(answerable.map(testCase => testCase.bestRelevant))}`,
    `- Chunk tidak relevan terbaik per kasus: ${stats(answerable.map(testCase => testCase.bestIrrelevant))}`,
    `- Chunk teratas pada kasus tanpa jawaban: ${stats(noAnswer.map(testCase => testCase.bestIrrelevant))}`,
    '',
    `Tidak masuk top ${HIT_RANK}:`
  );
  const missed = answerable.filter(
    testCase => !testCase.rank || testCase.rank > HIT_RANK
  );
  for (const testCase of missed) {
    lines.push(
      `- ${testCase.id}: ${testCase.rank ? `peringkat ${testCase.rank}` : 'tidak terambil'}`
    );
  }
  if (missed.length === 0) lines.push('- tidak ada');
  return lines.join('\n');
}

const files = process.argv.slice(2);
if (files.length === 0 || files.length > 2) {
  console.error(
    'Usage: node retrieval-report.mjs output/retrieval-a.json [output/retrieval-b.json]'
  );
  process.exit(1);
}

// Errored cases (HTTP or LLM errors) have no hits, so they are listed and left out of the metrics.
const runs = files.map(file => {
  const cases = loadRun(file);
  for (const testCase of cases.filter(candidate => candidate.error)) {
    console.error(`${file} ${testCase.id}: ${testCase.error}`);
  }
  return cases.filter(testCase => !testCase.error);
});
console.log(files.map((file, index) => report(file, runs[index])).join('\n\n'));

if (runs.length === 2) {
  const second = new Map(runs[1].map(testCase => [testCase.id, testCase]));
  const changed = runs[0].filter(
    testCase =>
      second.has(testCase.id) && second.get(testCase.id).pass !== testCase.pass
  );
  console.log('\n### Hasil berbeda antar-run\n');
  console.log(
    changed.length
      ? changed
          .map(
            testCase =>
              `- ${testCase.id}: ${files[0]} ${testCase.pass ? 'lulus' : 'gagal'}, ${files[1]} ${testCase.pass ? 'gagal' : 'lulus'}`
          )
          .join('\n')
      : '- tidak ada'
  );
}

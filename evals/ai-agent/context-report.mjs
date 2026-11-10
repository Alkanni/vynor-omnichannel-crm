// Summarizes multi-chunk context eval outputs (promptfooconfig.context.yaml, issue #133) as Markdown: per category the
// context recall (facts that reached the reply model), the full context rate (cases with every fact sent), and the
// completeness rubric; the control cases that sent noise; chunks, knowledge characters, input tokens, and latency per
// reply; and, for each fact that was not sent, how far its chunk is from the nearest chunk sent from the same source and
// section, which estimates what sending the neighbors of the sent chunks would add. The chunks come from the Knowledge
// Preview of the `konteks` agent, which also checks the chunk recorded for every fact and noise text. Given two runs, it
// lists the cases whose full context or completeness changed.
// Usage: node --env-file=.env context-report.mjs output/context-1.json [output/context-2.json]
import { readFileSync } from 'node:fs';
import { AGENTS_FILE, appApi } from './lib/app-api.mjs';
import { isSent, normalize, sentChunks } from './lib/context-assertions.mjs';

const AGENT = 'konteks';
const CONTROL = 'kontrol';
const RADII = [1, 2, 3];
// promptfoo's failureReason: 2 = the provider or the grader errored.
const FAILURE_REASON_ERROR = 2;

// The chunks of the agent's text sources in index order, per source title. A chunk's section is the heading path it opens
// with (see AiAgents::TextChunker) in a source with Markdown headings; a source without them is one section.
async function knowledgeChunks() {
  const agentId = JSON.parse(readFileSync(AGENTS_FILE, 'utf8'))[AGENT];
  const { payload: sources } = await appApi(
    `/ai_agents/${agentId}/knowledge_sources?source_type=text`
  );
  const entries = await Promise.all(
    sources.map(async source => {
      const { payload } = await appApi(
        `/ai_agents/${agentId}/knowledge_sources/${source.id}/chunks`
      );
      // A chunk is "<source title>\n\n<heading path>\n\n<text>"; heading paths below the top level contain " > ".
      const paths = payload.map(chunk => chunk.content.split('\n\n')[1] || '');
      const headed = paths.some(path => path.includes(' > '));
      const chunks = payload.map((chunk, index) => ({
        position: chunk.position,
        content: normalize(chunk.content),
        section: headed ? paths[index] : '',
      }));
      return [source.title, chunks];
    })
  );
  return new Map(entries);
}

// Positions of the chunks of a source that hold a text.
const holding = (chunks, text) =>
  chunks
    .filter(chunk => chunk.content.includes(normalize(text)))
    .map(chunk => chunk.position);

// Distance from an item's chunk to the nearest sent chunk of the same section, or null when that section sent none.
function distance(chunks, sentPositions, item) {
  const { section } = chunks[item.chunk - 1];
  const distances = sentPositions
    .filter(position => chunks[position - 1].section === section)
    .map(position => Math.abs(position - item.chunk));
  return distances.length ? Math.min(...distances) : null;
}

function loadRun(file, knowledge) {
  const { results } = JSON.parse(readFileSync(file, 'utf8'));
  return results.results.map(result => {
    const {
      id,
      category,
      source,
      facts,
      noise = [],
    } = result.testCase.metadata;
    const metadata = result.response?.metadata || {};
    const chunks = knowledge.get(source);
    const sent = sentChunks(metadata.retrieved, source);
    const sentPositions = chunks
      .filter(chunk => sent.includes(chunk.content))
      .map(chunk => chunk.position);
    const withDistance = item => {
      const itemSent = isSent(sent, item);
      return {
        ...item,
        sent: itemSent,
        distance: itemSent ? 0 : distance(chunks, sentPositions, item),
      };
    };
    const completeness = (result.gradingResult?.componentResults || []).find(
      component => component.assertion?.metric === 'completeness'
    );
    return {
      id,
      category,
      source,
      error:
        result.failureReason === FAILURE_REASON_ERROR ? result.error : null,
      facts: facts.map(withDistance),
      noise: noise.map(withDistance),
      sentPositions,
      unknownSent: sent.length - sentPositions.length,
      completeness: completeness?.pass,
      chunksSent: (metadata.retrieved || []).length,
      knowledgeCharacters: (metadata.retrieved || []).reduce(
        (sum, chunk) => sum + chunk.content.length,
        0
      ),
      inputTokens: result.response?.tokenUsage?.prompt,
      agentLatencyMs: metadata.agentLatencyMs,
    };
  });
}

const numbers = values => values.filter(Number.isFinite).sort((a, b) => a - b);

function stats(values) {
  const sorted = numbers(values);
  if (sorted.length === 0) return 'n/a';

  const average = Math.round(
    sorted.reduce((sum, value) => sum + value, 0) / sorted.length
  );
  const p90 = sorted[Math.ceil(sorted.length * 0.9) - 1];
  return `avg ${average}, p50 ${sorted[Math.floor(sorted.length / 2)]}, p90 ${p90}, max ${sorted[sorted.length - 1]} (n=${sorted.length})`;
}

const median = values => {
  const sorted = numbers(values);
  return sorted.length ? sorted[Math.floor(sorted.length / 2)] : 'n/a';
};

const share = (passed, total) =>
  total ? `${Math.round((passed / total) * 100)}% (${passed}/${total})` : 'n/a';

// An item counts as sent with radius r when it was sent or its chunk is at most r chunks from a sent chunk of its section.
const coveredBy = radius => item =>
  item.distance !== null && item.distance <= radius;
const fullContext = (testCase, radius = 0) =>
  testCase.facts.every(coveredBy(radius));

function categoryRow(category, scope) {
  const facts = scope.flatMap(testCase => testCase.facts);
  const graded = scope.filter(
    testCase => typeof testCase.completeness === 'boolean'
  );
  return [
    category,
    scope.length,
    share(facts.filter(fact => fact.sent).length, facts.length),
    share(scope.filter(testCase => fullContext(testCase)).length, scope.length),
    share(
      graded.filter(testCase => testCase.completeness).length,
      graded.length
    ),
    median(scope.map(testCase => testCase.chunksSent)),
    median(scope.map(testCase => testCase.knowledgeCharacters)),
  ];
}

function distanceCounts(facts) {
  const buckets = { 1: 0, 2: 0, 3: 0, '≥ 4': 0, 'bagian tidak terkirim': 0 };
  for (const { distance: value } of facts) {
    if (value === null) buckets['bagian tidak terkirim'] += 1;
    else if (value >= 4) buckets['≥ 4'] += 1;
    else buckets[value] += 1;
  }
  return Object.entries(buckets)
    .map(([bucket, count]) => `${bucket}: ${count}`)
    .join(', ');
}

function radiusEstimate(cases, multiChunk, controls) {
  return RADII.map(radius => {
    const facts = multiChunk.flatMap(testCase => testCase.facts);
    const covered = facts.filter(coveredBy(radius)).length;
    const full = cases.filter(testCase => fullContext(testCase, radius)).length;
    const polluted = controls.filter(testCase =>
      testCase.noise.some(coveredBy(radius))
    ).length;
    return `| ±${radius} | ${share(full, cases.length)} | ${share(covered, facts.length)} | ${share(polluted, controls.length)} |`;
  });
}

function caseRow(testCase) {
  const missing = testCase.facts
    .filter(fact => !fact.sent)
    .map(fact => `${fact.chunk}:${fact.distance ?? '-'}`)
    .join(', ');
  const noise = testCase.noise
    .filter(item => item.sent)
    .map(item => item.chunk)
    .join(', ');
  const completeness = { true: 'lulus', false: 'gagal' }[testCase.completeness];
  return `| ${testCase.id} | ${testCase.facts.filter(fact => fact.sent).length}/${testCase.facts.length} | ${missing || '-'} | ${noise || '-'} | ${completeness ?? 'n/a'} | ${testCase.sentPositions.join(', ') || '-'} | ${testCase.chunksSent} | ${testCase.knowledgeCharacters} |`;
}

function runReport(file, allCases) {
  const cases = allCases.filter(testCase => !testCase.error);
  const errors = allCases.filter(testCase => testCase.error);
  const controls = cases.filter(testCase => testCase.category === CONTROL);
  const multiChunk = cases.filter(testCase => testCase.category !== CONTROL);
  const categories = [...new Set(cases.map(testCase => testCase.category))];
  const lines = [
    `### ${file}: ${AGENT}`,
    '',
    '| Kategori | Kasus | Context recall (fakta) | Full context | Kelengkapan jawaban | Chunk terkirim (p50) | Karakter knowledge (p50) |',
    '|---|---|---|---|---|---|---|',
    ...[
      ...categories.map(category =>
        categoryRow(
          category,
          cases.filter(testCase => testCase.category === category)
        )
      ),
      categoryRow('Multi-chunk (tanpa kontrol)', multiChunk),
      categoryRow('Total', cases),
    ].map(row => `| ${row.join(' | ')} |`),
    '',
    `- Pollution, kasus kontrol yang mengirim chunk noise: ${share(controls.filter(testCase => testCase.noise.some(item => item.sent)).length, controls.length)}`,
    `- Chunk terkirim per balasan: ${stats(cases.map(testCase => testCase.chunksSent))}`,
    `- Karakter knowledge per balasan: ${stats(cases.map(testCase => testCase.knowledgeCharacters))}`,
    `- Input tokens per balasan: ${stats(cases.map(testCase => testCase.inputTokens))}`,
    `- Latency agent (ms): ${stats(cases.map(testCase => testCase.agentLatencyMs))}`,
    `- Jarak fakta yang tidak terkirim ke chunk terkirim terdekat dari sumber dan bagian yang sama: ${distanceCounts(cases.flatMap(testCase => testCase.facts.filter(fact => !fact.sent)))}`,
    '',
    'Perkiraan offline bila chunk tetangga dari bagian yang sama ikut terkirim, tanpa batas Context Limit (#134 membatasi total chunk dengan Context Limit, jadi angka ini batas atas):',
    '',
    '| Radius | Full context | Context recall multi-chunk | Kontrol dengan noise |',
    '|---|---|---|---|',
    ...radiusEstimate(cases, multiChunk, controls),
    '',
    'Per kasus (tidak terkirim = posisi chunk:jarak, `-` = bagiannya tidak terkirim sama sekali):',
    '',
    '| Kasus | Fakta terkirim | Tidak terkirim | Noise terkirim | Kelengkapan | Chunk sumber terkirim | Chunk total | Karakter |',
    '|---|---|---|---|---|---|---|---|',
    ...cases.map(caseRow),
  ];
  if (errors.length > 0) {
    lines.push(
      '',
      `${errors.length} kasus error tidak dihitung: ${errors.map(testCase => testCase.id).join(', ')}`
    );
  }
  return lines.join('\n');
}

// Every fact and noise text must sit in exactly the chunk recorded in the test case, and every sent chunk of a case's
// source must be one of the agent's chunks; otherwise the fixture or the chunking changed since the cases were written.
function fixtureCheck(cases, knowledge) {
  const problems = cases.flatMap(testCase => {
    const chunks = knowledge.get(testCase.source);
    const misplaced = [...testCase.facts, ...testCase.noise]
      .filter(item => {
        const found = holding(chunks, item.text);
        return found.length !== 1 || found[0] !== item.chunk;
      })
      .map(
        item =>
          `${testCase.id}: "${item.text}" tercatat di chunk ${item.chunk}, ditemukan di ${holding(chunks, item.text).join(', ') || 'tidak ada'}`
      );
    const unknown =
      testCase.unknownSent > 0
        ? [
            `${testCase.id}: ${testCase.unknownSent} chunk terkirim tidak ada di Knowledge Preview`,
          ]
        : [];
    return [...misplaced, ...unknown];
  });
  return [
    '### Pemeriksaan fixture',
    '',
    problems.length
      ? problems.map(problem => `- ${problem}`).join('\n')
      : '- Semua fakta dan noise ada tepat di chunk yang tercatat.',
  ].join('\n');
}

const files = process.argv.slice(2);
if (files.length === 0 || files.length > 2) {
  console.error(
    'Usage: node --env-file=.env context-report.mjs output/context-1.json [output/context-2.json]'
  );
  process.exit(1);
}

const knowledge = await knowledgeChunks();
const runs = files.map(file => loadRun(file, knowledge));
console.log(
  [
    fixtureCheck(runs[0], knowledge),
    ...files.map((file, index) => runReport(file, runs[index])),
  ].join('\n\n')
);

if (runs.length === 2) {
  const second = new Map(runs[1].map(testCase => [testCase.id, testCase]));
  const changed = runs[0].flatMap(testCase => {
    const other = second.get(testCase.id);
    if (!other || testCase.error || other.error) return [];

    const changes = [];
    if (fullContext(testCase) !== fullContext(other))
      changes.push(
        `full context ${fullContext(testCase) ? 'ya' : 'tidak'} → ${fullContext(other) ? 'ya' : 'tidak'}`
      );
    if (testCase.completeness !== other.completeness)
      changes.push(
        `kelengkapan ${testCase.completeness ? 'lulus' : 'gagal'} → ${other.completeness ? 'lulus' : 'gagal'}`
      );
    return changes.length ? [`- ${testCase.id}: ${changes.join('; ')}`] : [];
  });
  console.log('\n### Hasil berbeda antar-run\n');
  console.log(changed.length ? changed.join('\n') : '- tidak ada');
}

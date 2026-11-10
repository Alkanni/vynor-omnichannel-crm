// The assertions of promptfooconfig.context.yaml (issue #133) and the rules context-report.mjs shares with them, over the
// metadata of provider.mjs. A case's `facts` and `noise` (test metadata) are texts of chunks of its `source`; whitespace
// compares as one space, because text extracted from a PDF breaks its lines anywhere.
export const normalize = text => text.replace(/\s+/g, ' ').trim();

// The normalized content of the chunks the reply model got from a source.
export function sentChunks(retrieved, source) {
  return (retrieved || [])
    .filter(chunk => chunk.source.title === source)
    .map(chunk => normalize(chunk.content));
}

export const isSent = (chunks, { text }) =>
  chunks.some(chunk => chunk.includes(normalize(text)));

const describe = items =>
  items.map(({ chunk, text }) => `chunk ${chunk} "${text}"`).join('; ');

// Every fact of the case reached the reply model.
export function sentFacts(_output, { test, metadata }) {
  const { source, facts } = test.metadata;
  const chunks = sentChunks(metadata.retrieved, source);
  const missing = facts.filter(fact => !isSent(chunks, fact));
  return {
    pass: missing.length === 0,
    score: 1 - missing.length / facts.length,
    reason: missing.length
      ? `Tidak terkirim: ${describe(missing)}`
      : 'Semua fakta terkirim',
  };
}

// None of the noise texts of a control case reached the reply model.
export function noNoise(_output, { test, metadata }) {
  const { source, noise } = test.metadata;
  const chunks = sentChunks(metadata.retrieved, source);
  const sent = noise.filter(item => isSent(chunks, item));
  return {
    pass: sent.length === 0,
    score: sent.length ? 0 : 1,
    reason: sent.length
      ? `Noise terkirim: ${describe(sent)}`
      : 'Tidak ada noise terkirim',
  };
}

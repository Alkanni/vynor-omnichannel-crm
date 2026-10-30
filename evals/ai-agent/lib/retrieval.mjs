// Shared rules for retrieval cases. `expected` lists the acceptable source titles (knowledge source title or product
// name), one per line; a case without `expected` has no answer in the knowledge.
export const HIT_RANK = 5;

export function expectedTitles(vars) {
  return (vars.expected || '')
    .split('\n')
    .map(title => title.trim())
    .filter(Boolean);
}

// Rank of the best hit from an expected source, or null when none was retrieved.
export function firstExpectedRank(hits, expected) {
  return hits.find(hit => expected.includes(hit.title))?.rank ?? null;
}

// Promptfoo javascript assertion: an expected source must rank within HIT_RANK; a case without an answer passes only
// when nothing was retrieved.
export default function assertRetrieval(_output, { vars, metadata }) {
  const expected = expectedTitles(vars);
  if (expected.length === 0) {
    const pass = metadata.hits.length === 0;
    return {
      pass,
      score: pass ? 1 : 0,
      reason: pass
        ? 'Nothing retrieved'
        : `${metadata.hits.length} chunks retrieved without an answer in the knowledge (top score ${metadata.hits[0].score})`,
    };
  }

  const rank = firstExpectedRank(metadata.hits, expected);
  return {
    pass: rank !== null && rank <= HIT_RANK,
    score: rank ? 1 / rank : 0,
    reason: rank
      ? `Expected source at rank ${rank}`
      : `Expected source not among the ${metadata.hits.length} chunks retrieved`,
  };
}

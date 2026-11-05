// The link assertions of promptfooconfig.web.yaml and the input of its web_claims judge, over the metadata of provider.mjs.
import { linkKey, links } from './links.mjs';

// Every link in the reply is the link of a web result or is in the knowledge chunks the reply model had.
export function knownLinks(output, { metadata }) {
  const known = new Set(
    [
      ...metadata.webResults.map(({ url }) => url),
      ...metadata.knowledgeLinks,
    ].map(linkKey)
  );
  return links(output).every(link => known.has(linkKey(link)));
}

// What the judge of the `web_claims` rubric grades: the reply with the web results it cites and the knowledge chunks the
// reply model had, as their text reached the model.
export function judgeInput(output, { metadata }) {
  const cited = metadata.webResults.filter(({ rank }) =>
    (metadata.citedRanks || []).includes(rank)
  );
  const webResults = cited.map(
    ({ rank, title, url, publishedAt, text }) =>
      `[${rank}] ${title} (${publishedAt?.slice(0, 10) || 'tanpa tanggal'})\n${url}\n${text}`
  );
  const knowledge = (metadata.retrieved || []).map(
    ({ rank, source, content }) => `[${rank}] ${source.title}\n${content}`
  );
  return [
    `<Reply>\n${output}\n</Reply>`,
    `<CitedWebResults>\n${webResults.join('\n\n') || '(tidak ada)'}\n</CitedWebResults>`,
    `<Knowledge>\n${knowledge.join('\n\n') || '(tidak ada)'}\n</Knowledge>`,
  ].join('\n');
}

// A reply that was sent has the link of every web result it cites; one the reply check replaced has no citations left.
export function citedLinks(output, { metadata }) {
  if (metadata.blockedReason) return true;

  const reply = output.toLowerCase();
  return metadata.webResults
    .filter(({ rank }) => (metadata.citedRanks || []).includes(rank))
    .every(({ url }) => reply.includes(linkKey(url)));
}

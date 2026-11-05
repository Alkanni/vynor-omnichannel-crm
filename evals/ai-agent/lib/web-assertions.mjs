// The link assertions of promptfooconfig.web.yaml, over the metadata of provider.mjs.
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

// A reply that was sent has the link of every web result it cites; one the reply check replaced has no citations left.
export function citedLinks(output, { metadata }) {
  if (metadata.blockedReason) return true;

  const reply = output.toLowerCase();
  return metadata.webResults
    .filter(({ rank }) => (metadata.citedRanks || []).includes(rank))
    .every(({ url }) => reply.includes(linkKey(url)));
}

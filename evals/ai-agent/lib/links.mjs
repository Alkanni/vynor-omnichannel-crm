// Links in a text, compared the way AiAgents::ReplyValidator compares them: a link with its scheme or "www.", keyed
// without the scheme, "www.", a trailing slash, the punctuation after it in a sentence, or case.
const LINK = /\b(?:https?:\/\/|www\.)[^\s<>"'`*[\]]+/gi;

export const linkKey = link =>
  link
    .toLowerCase()
    .replace(/^(?:https?:\/\/)?(?:www\.)?/, '')
    .replace(/[/.,;:!?)]+$/, '');

export const links = text => (text || '').match(LINK) || [];

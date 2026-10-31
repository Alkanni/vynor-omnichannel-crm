// A case's `conversation` has one message per line; lines starting with "AI:" are earlier agent replies.
const ASSISTANT_PREFIX = 'AI:';

export function toMessages(conversation) {
  return conversation
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .map(line =>
      line.startsWith(ASSISTANT_PREFIX)
        ? {
            role: 'assistant',
            content: line.slice(ASSISTANT_PREFIX.length).trim(),
          }
        : { role: 'user', content: line }
    );
}

// What the Retrieval Test takes: the customer messages since the last agent reply as the question, and the messages
// before them as history.
export function toRetrievalTest(conversation) {
  const messages = toMessages(conversation);
  const lastReply = messages.findLastIndex(
    message => message.role === 'assistant'
  );
  return {
    history: messages.slice(0, lastReply + 1),
    query: messages
      .slice(lastReply + 1)
      .map(message => message.content)
      .join('\n'),
  };
}

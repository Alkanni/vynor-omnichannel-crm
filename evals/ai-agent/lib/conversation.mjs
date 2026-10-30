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

// The retrieval query a reply uses today: the customer messages since the last agent reply
// (AiAgents::ReplyGenerator#latest_customer_text).
export function runtimeQuery(conversation) {
  const messages = toMessages(conversation);
  const lastReply = messages.findLastIndex(
    message => message.role === 'assistant'
  );
  return messages
    .slice(lastReply + 1)
    .map(message => message.content)
    .join('\n');
}

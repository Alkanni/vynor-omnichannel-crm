// Promptfoo provider that sends a dataset conversation to the AI Agent playground of the app under test.
// Each line of `conversation` is one message; lines starting with "AI:" are earlier agent replies.
// The reply text is the output; handoff, labels, the scope check, retrieval, model and latency go to metadata for
// assertions. Retrieval is empty when the scope check answered the turn.
import { readFileSync } from 'node:fs';
import { AGENTS_FILE, appApi } from './lib/app-api.mjs';
import { toMessages } from './lib/conversation.mjs';

export default class AiAgentPlaygroundProvider {
  // `config.agent` fixes the agent, so one config can run the same cases against several agent variants.
  constructor({ config = {} } = {}) {
    this.agent = config.agent;
  }

  id() {
    return 'ai-agent-playground';
  }

  async callApi(_prompt, { vars }) {
    const agentId = JSON.parse(readFileSync(AGENTS_FILE, 'utf8'))[
      this.agent || vars.agent
    ];
    try {
      const reply = await appApi(`/ai_agents/${agentId}/playground`, {
        method: 'POST',
        body: { messages: toMessages(vars.conversation) },
      });
      const { input, output } = reply.tokens;
      return {
        output: reply.messages.join('\n'),
        tokenUsage:
          input == null
            ? undefined
            : { prompt: input, completion: output, total: input + output },
        metadata: {
          handoff: reply.handoff,
          labels: reply.labels,
          model: reply.model,
          agentLatencyMs: reply.latency_ms,
          scopeDecision: reply.scope?.decision,
          scopeLatencyMs: reply.scope?.latency_ms,
          retrievalMode: reply.retrieval?.mode,
          retrieved: (reply.retrieval?.chunks || []).map(
            ({ rank, score, source }) => ({ rank, score, source })
          ),
        },
      };
    } catch (error) {
      return { error: error.message };
    }
  }
}

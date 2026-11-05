// Promptfoo provider that sends a dataset conversation to the AI Agent playground of the app under test.
// Each line of `conversation` is one message; lines starting with "AI:" are earlier agent replies.
// The reply text is the output; handoff, labels, the scope check (with the web query of an agent with web search), what
// became of web search with each web result as the reply model got it, the reply check, retrieval with the content and
// links of its chunks, model, latency and the tokens per model call go to metadata for assertions and report.mjs.
// Retrieval is empty when the scope check answered the turn, so the reply model ran only when it is there, and the reply
// check runs only for a strict agent's reply model. The token usage adds up the scope check and the reply model; cached input tokens are not part of it.
import { readFileSync } from 'node:fs';
import { AGENTS_FILE, appApi } from './lib/app-api.mjs';
import { toMessages } from './lib/conversation.mjs';
import { links } from './lib/links.mjs';

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
          webQuery: reply.scope?.web_query,
          // The search's status when the turn was searched, else the scope check's.
          webSearchStatus: reply.web?.status ?? reply.scope?.web_search_status,
          webResults: (reply.web?.results || []).map(
            ({ rank, title, url, published_at: publishedAt, text }) => ({
              rank,
              title,
              url,
              publishedAt,
              text,
            })
          ),
          webLatencyMs: reply.web?.latency_ms,
          webCostUsd: reply.web?.cost_usd,
          scopeLatencyMs: reply.scope?.latency_ms,
          scopeInputTokens: reply.scope?.input_tokens,
          scopeOutputTokens: reply.scope?.output_tokens,
          cachedInputTokens: reply.tokens.cached_input,
          replyModel: reply.retrieval != null,
          replyDecision: reply.validation?.decision,
          citedRanks: reply.validation?.sources,
          blockedReason: reply.validation?.blocked_reason,
          retrievalMode: reply.retrieval?.mode,
          retrieved: (reply.retrieval?.chunks || []).map(
            ({ rank, score, source, content }) => ({
              rank,
              score,
              source,
              content,
            })
          ),
          knowledgeLinks: (reply.retrieval?.chunks || []).flatMap(
            ({ content }) => links(content)
          ),
        },
      };
    } catch (error) {
      return { error: error.message };
    }
  }
}

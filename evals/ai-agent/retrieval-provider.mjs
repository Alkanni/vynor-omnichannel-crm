// Promptfoo provider for retrieval cases: sends the conversation (lib/conversation.mjs) to the agent's Retrieval
// Test, which runs AiAgents::KnowledgeRetriever exactly as a reply does, and returns the ranked
// sources. No chat model is called; in hybrid mode only the query is embedded.
import { readFileSync } from 'node:fs';
import { AGENTS_FILE, appApi } from './lib/app-api.mjs';
import { toRetrievalTest } from './lib/conversation.mjs';

const SHOWN_HITS = 5;

export default class RetrievalTestProvider {
  id() {
    return 'ai-agent-retrieval-test';
  }

  async callApi(_prompt, { vars }) {
    const agentId = JSON.parse(readFileSync(AGENTS_FILE, 'utf8'))[
      vars.agent || 'large'
    ];
    try {
      const startedAt = performance.now();
      const retrieval = await appApi(`/ai_agents/${agentId}/retrieval_test`, {
        method: 'POST',
        body: toRetrievalTest(vars.conversation),
      });
      const latencyMs = Math.round(performance.now() - startedAt);
      const hits = retrieval.chunks.map(
        ({ rank, score, distance, content, source }) => ({
          rank,
          score,
          distance,
          content,
          sourceType: source.type,
          title: source.title,
        })
      );
      return {
        output: hits
          .slice(0, SHOWN_HITS)
          .map(hit => `${hit.rank}. ${hit.title} (${hit.score})`)
          .join('\n'),
        metadata: {
          queries: retrieval.queries,
          mode: retrieval.mode,
          embeddingModel: retrieval.embedding_model,
          contextLimit: retrieval.context_limit,
          latencyMs,
          hits,
        },
      };
    } catch (error) {
      return { error: error.message };
    }
  }
}

# Module: AI Agent (fork feature, CE)

Commit `a9068db6` + issues #70, #72, #71. Status: **VERIFIED** from source. The fork's own knowledge-based auto-reply agent (epic #32, v2 roadmap epic #69). It is separate from Enterprise Captain; it reuses only the LLM settings (`CAPTAIN_OPEN_AI_*`) and RubyLLM.

## Where things live

| Concern | Location |
|---|---|
| Models | `app/models/ai_agent.rb`, `app/models/ai_agent/{knowledge_source,product,knowledge_chunk,integration,reply_trace}.rb`, `app/models/ai_agent_inbox.rb` |
| API | `Api::V1::Accounts::AiAgentsController` (CRUD, `models`, `duplicate`, `train`, `playground`, `retrieval_test`), `Api::V1::Accounts::AiAgents::{KnowledgeSources,Products,GoogleSheets}Controller`; admin-only via `AiAgentPolicy` |
| Runtime | `AiAgentListener` → `AiAgents::ReplyJob` → `AiAgents::ReplyGenerator` (+ `KnowledgeRetriever`, `ActionSchema`, `LlmClient`) → `AiAgents::ConversationSession` |
| Knowledge pipeline | `ProcessKnowledgeSourceJob` (website via `WebPageFetcher`/`WebsiteContentExtractor`, file via `FileTextExtractor`) → `IndexKnowledgeJob` → `KnowledgeIndexer` + `TextChunker` |
| Follow-up jobs | `WatchJob` (`Watcher`, second LLM look for missed handoff/labels), `AppendSheetRowJob` (Google Sheets) |
| Frontend | `app/javascript/dashboard/routes/dashboard/aiAgents/`, API clients `api/aiAgents.js`, `api/aiAgentKnowledge.js`, `api/aiAgentGoogleSheets.js`, i18n `i18n/locale/en/aiAgents.json` |

## Reply flow

1. `AiAgentListener#message_created`: for an incoming message in an inbox connected to an agent, while `ConversationSession#ai_active?`, queue `ReplyJob` after `message_await` seconds; otherwise send the pending message.
2. `ReplyJob#perform`: only the job for the newest incoming message answers (bursts get one reply). If the session reached `message_limit`, hand off (`:message_limit`).
3. `ReplyGenerator#perform`: instructions = behavior + local time + `<knowledge>` + action instructions; history from `ConversationSession#history` (`history_limit`, images per `read_file_limit`). One LLM call with a forced function call (`ReplyTool`), because some gateways drop `response_format`.
4. `ReplyJob#deliver`: send bubbles (unless silent handoff), apply labels/sheet row/handoff, queue `WatchJob`, then write an `AiAgent::ReplyTrace`. Any error hands off (`:error`) and writes an `error` trace.

## Retrieval (`AiAgents::KnowledgeRetriever`)

- Query: the customer messages since the last reply (`ReplyGenerator#latest_customer_text`, max 4,000 characters). No conversation context yet.
- Vector mode when `AI_AGENT_EMBEDDING_MODEL` is set: pgvector cosine `nearest_neighbors`, only chunks with the current `embedding_model` (`KnowledgeChunk.searchable`); score = cosine distance (lower is closer).
- Keyword mode otherwise: `KnowledgeChunk.keyword_ranked`, `ts_rank` with the `simple` text search config and OR-joined terms (not BM25); score = `keyword_rank` (higher is closer).
- Always returns the top `context_limit` (default 40) chunks; no relevance threshold, no hybrid fusion (planned in epic #69, Phase 2).
- Chunking (`TextChunker`): paragraphs packed up to 1,500 characters, title prefixed; Q&A and products are one chunk each.

## Reply traces (`ai_agent_reply_traces`)

One row per answered customer message: `status` (`replied`, `handoff`, `message_limit`, `error`), `model`, `retrieval_mode`, `embedding_model`, `retrieved` (jsonb list of `chunk_id`, `chunkable_type`, `chunkable_id`, `rank`, `score`), `labels`, `input_tokens`/`output_tokens` (nil when the gateway sends no `usage`), `latency_ms` (retrieval + model call), `error_class`. No message or chunk content is stored. Rows are deleted with their agent or conversation (`dependent: :delete_all`); no time-based retention. Not written for the Watcher call, for the playground, or when a reply is dropped because the customer wrote again.

## Knowledge Preview and Retrieval Test

- `GET /api/v1/accounts/:account_id/ai_agents/:ai_agent_id/knowledge_sources/:id/chunks` returns the source's chunks in index order (`position`, `content`, `embedding_model`, `indexed_at`, and `searchable` per `KnowledgeChunk.searchable`) plus the current `embedding_model`. The UI opens it from the layers button on Text, Website, File, and Q&A sources (`SourceChunksDialog.vue`).
- `POST /api/v1/accounts/:account_id/ai_agents/:id/retrieval_test` with `query` (non-blank string, at most `ReplyGenerator::MAX_QUERY_CHARACTERS`) runs `KnowledgeRetriever` exactly as a reply does and returns `context_limit` plus the same `retrieval` shape as the playground. The UI is the "Test retrieval" button on the Knowledge Sources page (`RetrievalTestDialog.vue`).

## Playground

`POST /api/v1/accounts/:account_id/ai_agents/:id/playground` with `messages` (user/assistant, max 100, 10,000 characters each) returns `messages`, `handoff`, `labels`, `sheet_row`, `model`, `retrieval` (`mode`, `embedding_model`, `chunks` with `rank`, `score`, `content`, `source {id, type, title}`), `tokens {input, output}`, `latency_ms`. It writes no trace.

## Evaluation

`evals/ai-agent/` (issue #71) is a Promptfoo regression eval against the playground, outside the app bundle (`npx promptfoo@0.124.1`). `setup.mjs` recreates eval agents from `fixtures/toko-roti.json` through the API; `provider.mjs` sends each case's conversation (lines starting with `AI:` become assistant messages) and exposes `handoff`, `labels`, and retrieval as metadata for assertions; `llm-rubric` cases use a judge model from `.env`. See its README for running and comparing baselines.

## Configuration

Installation configs (Super Admin): `CAPTAIN_OPEN_AI_API_KEY`, `CAPTAIN_OPEN_AI_ENDPOINT`, `AI_AGENT_MODELS` (gateway model IDs), `AI_AGENT_EMBEDDING_MODEL`, `AI_AGENT_EMBEDDING_ENDPOINT`, `AI_AGENT_EMBEDDING_API_KEY`. Per-agent settings are the `AiAgentsController::SETTINGS` columns.

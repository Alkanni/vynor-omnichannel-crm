# AI Agent eval (Promptfoo)

Regression evals for the AI Agent, run against a running app:

- **End-to-end** (issue #71): each case sends a conversation to the AI Agent playground and checks the reply text,
  the handoff decision, and the labels.
- **Retrieval** (issue #80): each case runs a question through the agent's Retrieval Test and checks where the
  expected knowledge source ranks. No chat model is called.

Run them before and after changes to behavior, models, chunking, or retrieval, and compare the results.

Promptfoo runs through `npx` with a pinned version, so nothing is added to the app's `package.json`. Every LLM call
uses real tokens: one run makes 47 agent calls plus 38 judge calls.

## Files

| Path | Content |
|---|---|
| `promptfooconfig.yaml` | Provider, judge model, judge prompt, and the test files |
| `tests/*.yaml` | 47 cases in five categories: A1 grounding, A2 security, A3 multi-turn, A4 actions (handoff/labels), B knowledge facts |
| `fixtures/toko-roti.json` | Settings, knowledge, product, and label of the eval agents (the "CS Toko Roti Vynor" UAT agent, temperature `precise`) |
| `fixtures/toko-roti-large.json` | Synthetic larger knowledge for the retrieval eval (44 chunks: policy text with headings, a price table longer than one chunk, 16 Q&A, 22 products) |
| `setup.mjs` | Recreates the eval agents of the fixtures through the API and waits until their knowledge is indexed |
| `provider.mjs` | Sends each case to `POST /api/v1/accounts/:account_id/ai_agents/:id/playground` |
| `report.mjs` | Markdown summary: pass rate per category, tokens, latency, failures, and results that changed between two runs |
| `promptfooconfig.retrieval.yaml`, `tests/retrieval.yaml` | Retrieval eval: 32 cases (direct, paraphrase, typo, table/heading, multi-turn, no answer) |
| `retrieval-provider.mjs` | Sends each case to `POST /api/v1/accounts/:account_id/ai_agents/:id/retrieval_test` |
| `retrieval-report.mjs` | Markdown summary: hit@1, hit@5, MRR per category, chunks retrieved, and score distribution of relevant vs irrelevant chunks |
| `lib/` | API client, conversation parsing (shared by both providers), retrieval assertion |

The cases come from the Claude Doc "Draf Dataset Eval AI Agent" (2026-10-28). The team had not reviewed it yet, so
every case is still the draft. Case IDs (`A1-01`, `B-07`, …) match the document. Notes that wait for a team decision
are YAML comments above the case, not part of the rubric.

## Prerequisites

- Node.js 22.22 or newer (Promptfoo 0.124.1).
- A running app with the AI Agent configured in Super Admin (LLM endpoint and key, `AI_AGENT_MODELS`, optional
  `AI_AGENT_EMBEDDING_MODEL`) and Sidekiq running, because knowledge is indexed by a background job.
- An administrator access token for the account. The playground is admin-only.
- An OpenAI-compatible endpoint and key for the judge model.

## Run

```bash
cd evals/ai-agent
cp .env.example .env   # fill in the URL, account id, access token, and judge settings
node --env-file=.env setup.mjs
npx promptfoo@0.124.1 eval --no-cache -o output/run-1.json
node report.mjs output/run-1.json
```

`setup.mjs` sets up every fixture in `fixtures/` unless fixture file names are given (for example
`node --env-file=.env setup.mjs toko-roti-large.json`). It deletes and recreates only the agents named in those
fixtures, creates the `komplain` label if it is missing, and merges the agent ids into `.eval-agents.json`. Run it
again after changing a fixture. The `injection` agent has an extra knowledge source with an embedded instruction and
is used only by A2-09; the `large` agent is used by the retrieval eval.

`npx promptfoo@0.124.1 view` opens the results in the browser, including each judge reason.

## Reading the results

- A case passes when all its assertions pass. An error means the playground or the judge call failed (HTTP error, LLM
  error); it is not a quality failure.
- `llm-rubric` asks the judge whether the reply meets the expected behavior. The judge sees the conversation, the test
  time (for B-12), the reply, and the rubric. `icontains` and `not-icontains` are text checks.
- A4 cases check `handoff` and `labels` from the playground response with `javascript` assertions.
- Tokens and latency come from the playground response (`tokens`, `latency_ms`), which uses the same measurement as
  `ai_agent_reply_traces`. The playground itself writes no trace.

## Baseline and flaky cases

Run the eval twice in a row and compare:

```bash
npx promptfoo@0.124.1 eval --no-cache -o output/run-2.json
node report.mjs output/run-1.json output/run-2.json
```

Cases whose result differs between the runs are flaky candidates. Mark them in the test file with
`metadata: { …, flaky: true }`; the report labels them so a single failure is not read as a regression.

## Retrieval eval

```bash
npx promptfoo@0.124.1 eval -c promptfooconfig.retrieval.yaml --no-cache -o output/retrieval-vector.json
node retrieval-report.mjs output/retrieval-vector.json
```

- `expected` in `tests/retrieval.yaml` lists the acceptable sources (knowledge source title or product name), one per
  line. A case passes when one of them ranks in the top 5. A case without `expected` has no answer in the knowledge
  and passes only when nothing is retrieved.
- Multi-turn cases search with the query a reply builds today: the customer messages after the last `AI:` line.
- The mode follows `AI_AGENT_EMBEDDING_MODEL` in Super Admin: vector when it is set, keyword when it is blank. To
  measure keyword mode, blank it, run the eval, and set it back. This affects every agent of the installation while it
  is blank, but no re-index is needed. Vector scores are cosine distances (lower is closer); keyword scores are
  `ts_rank` (higher is closer).
- Each case costs one embedding call in vector mode and no LLM call in keyword mode. Results are deterministic for the
  same knowledge, so two runs that differ point to a setup problem.
- Pass two outputs to `retrieval-report.mjs` to list the cases whose result changed, for example before and after a
  retrieval change.

## Changing the dataset

Edit the case in `tests/` and keep the ID in sync with the dataset document. To test real business knowledge, change
`fixtures/toko-roti.json` (or add a fixture), run `setup.mjs` again, and replace the B cases. Output in `output/`,
`.env`, and `.eval-agents.json` are git-ignored; never commit tokens or keys.

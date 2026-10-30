# AI Agent eval (Promptfoo)

Regression eval for the AI Agent (issue #71). Each case sends a conversation to the AI Agent playground of a running
app and checks the reply text, the handoff decision, and the labels. Run it before and after changes to behavior,
models, chunking, or retrieval, and compare the results.

Promptfoo runs through `npx` with a pinned version, so nothing is added to the app's `package.json`. Every LLM call
uses real tokens: one run makes 47 agent calls plus 38 judge calls.

## Files

| Path | Content |
|---|---|
| `promptfooconfig.yaml` | Provider, judge model, judge prompt, and the test files |
| `tests/*.yaml` | 47 cases in five categories: A1 grounding, A2 security, A3 multi-turn, A4 actions (handoff/labels), B knowledge facts |
| `fixtures/toko-roti.json` | Settings, knowledge, product, and label of the eval agents (the "CS Toko Roti Vynor" UAT agent, temperature `precise`) |
| `setup.mjs` | Recreates the eval agents through the API and waits until their knowledge is indexed |
| `provider.mjs` | Sends each case to `POST /api/v1/accounts/:account_id/ai_agents/:id/playground` |
| `report.mjs` | Markdown summary: pass rate per category, tokens, latency, failures, and results that changed between two runs |

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

`setup.mjs` deletes and recreates only the agents named in the fixture ("Eval - CS Toko Roti Vynor" and its
`injection` copy), creates the `komplain` label if it is missing, and writes the agent ids to `.eval-agents.json`.
Run it again after changing the fixture. The `injection` agent has an extra knowledge source with an embedded
instruction and is used only by A2-09.

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

## Changing the dataset

Edit the case in `tests/` and keep the ID in sync with the dataset document. To test real business knowledge, change
`fixtures/toko-roti.json` (or add a fixture), run `setup.mjs` again, and replace the B cases. Output in `output/`,
`.env`, and `.eval-agents.json` are git-ignored; never commit tokens or keys.

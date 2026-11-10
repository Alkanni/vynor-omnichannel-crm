# .ai-context — Codebase Intelligence for vynor-omnichannel-crm

> **Analyzed commit:** `9f920b549c14491a4e587687a3eed5d21c6ccc7d` (Merge branch 'release/4.18.0', 2026-09-17)
> **Analysis date:** 2026-10-20 · **Method:** static source reading only (rg/grep/sed). No Ruby runtime, no LSP, no execution.
> **Staleness check:** `git rev-parse HEAD` — if it differs, run `git diff --stat 9f920b54..HEAD` and treat docs touching changed paths as stale.

## What this repository is (VERIFIED)

This is a **fork of Chatwoot v4.18.0** with **zero local modifications** at the analyzed commit.
`origin` = `github.com/Alkanni/vynor-omnichannel-crm`, `upstream` = `github.com/chatwoot/chatwoot`;
every commit in `git log` is upstream authorship; no "vynor" string exists anywhere in the tree.
Everything documented here is therefore upstream Chatwoot architecture — the starting point for future Vynor customization.

- **Backend:** Ruby 3.4.4 / Rails 8.0.5.2 (`load_defaults 7.0`, schema header 7.1) monolith, PostgreSQL (+pgvector, pg_trgm), Redis, Sidekiq.
- **Frontend:** Vue 3 + Vite, mixed Vuex (`dashboard/store`) and Pinia (`dashboard/stores`) state.
- **Overlay:** `enterprise/` (separately licensed) extends OSS classes at load time via `prepend_mod_with`.

## How to use this knowledge base

1. Start here, then open [`index.yaml`](index.yaml) to find the document for your task.
2. Load only the relevant documents. Typical entry points:

| Task | Read |
|---|---|
| "Where is X?" / orientation | [system-overview.md](system-overview.md), [module-catalog.md](module-catalog.md) |
| Change a message/conversation behavior | [flows/inbound-message.md](flows/inbound-message.md), [flows/outbound-reply.md](flows/outbound-reply.md), [flows/event-bus.md](flows/event-bus.md) |
| Add/modify an API endpoint | [api-map.md](api-map.md), [flows/request-auth.md](flows/request-auth.md) |
| DB/schema work | [database-map.md](database-map.md) |
| Rebrand / customize the fork | [customization-surfaces.md](customization-surfaces.md), [modules/enterprise-overlay.md](modules/enterprise-overlay.md) |
| AI Agent (knowledge, retrieval, replies) | [modules/ai-agent.md](modules/ai-agent.md) |
| Assess blast radius before editing | [change-impact-guide.md](change-impact-guide.md), [dependency-map.md](dependency-map.md) |
| Known gaps / risks | [risks-and-unknowns.md](risks-and-unknowns.md) |

3. **Verify against source before editing.** Line numbers are as of the analyzed commit.

## Confidence legend

- **VERIFIED** — read directly in source at the cited path/line.
- **INFERRED** — reasonable reading of code, not traced end-to-end or not runtime-checked.
- **UNKNOWN** — insufficient evidence; listed in [risks-and-unknowns.md](risks-and-unknowns.md).

## Maintenance

After a verified code change, update the affected docs and bump `last_analyzed_commit` for those entries in `index.yaml`.
Keep docs as navigation (paths, symbols, relationships) — do not paste source code.

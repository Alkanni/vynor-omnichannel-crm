# Risks and Unknowns

Commit `9f920b54`.

## Architectural risks (VERIFIED basis)

| # | Risk | Evidence | Why it matters |
|---|---|---|---|
| R1 | **Callback-driven side effects** in `Message`/`Conversation` | `app/models/message.rb:324-333`, `app/models/conversation.rb:268-274` | Hidden coupling; `update_column`/bulk writes silently skip events; order-dependent (comment cites rails/rails#20911) |
| R2 | **Application-only referential integrity** (8 FKs / 98 tables) | `db/schema.rb:1599-1606` | Orphans possible; cron `RemoveOrphanConversationsJob` exists to clean them (`config/schedule.yml`) |
| R3 | **Row-level multi-tenancy without DB enforcement** | `account_id` columns; `EnsureCurrentAccountHelper` | Any unscoped query leaks cross-tenant data; requires discipline/review |
| R4 | **Feature flag bit ordering** | `config/features.yml:1-14`, `featurable.rb:15-28` | Reordering/removing a flag flips features for all accounts |
| R5 | **Premium branding/feature reset** on community plan | `enterprise/app/services/internal/reconcile_plan_config_service.rb:2-10` | Rebranding via installation config is reverted daily in production |
| R6 | **Enterprise license** on `enterprise/` | `enterprise/LICENSE` | Legal constraint on modifying/using EE code in a commercial fork |
| R7 | **External telemetry/hub sync** | `app/jobs/internal/check_new_versions_job.rb:4-8`, `lib/chatwoot_hub.rb` | Production instance contacts Chatwoot Hub daily; sets plan configs |
| R8 | **Strict-priority Sidekiq queues** | `config/sidekiq.yml` | High-queue floods starve webhooks/housekeeping |
| R9 | **Async events carry AR objects** | `message.rb:380`, `async_dispatcher.rb:3` | Deleted records → job deserialization errors (INFERRED) |
| R10 | **Dual frontend state (Vuex + Pinia)** | `entrypoints/dashboard.js:43-51` | Two patterns to follow; migration in flux |
| R11 | **`custom/` extension slot not on load paths** | `lib/chatwoot_app.rb:32-48` vs `config/application.rb:42-50` | Using it requires extra wiring (INFERRED) |
| R12 | **High-coupling models** (`Conversation` 111 files, `Account` 113, `Current` 159) | [dependency-map.md](dependency-map.md) | Changes ripple widely |
| R13 | **Upstream drift** | fork = upstream v4.18.0 | Customizations in hotspot files increase merge cost |

## Unknowns (not analyzed / not verifiable statically)

- Runtime behavior of all flows (no Ruby on host; nothing executed). All sequence diagrams are static traces.
- Per-channel incoming services other than WhatsApp/widget/email (Facebook, Instagram, Telegram, LINE, TikTok, SMS, Twitter, Shopify, voice).
- `Conversations::UnreadCounts::Listener` and filtered unread-count caching.
- `AssignmentHandler` concern internals (assignee/team change events).
- Captain v2 agent runner tool loop, credit/usage accounting, `more_responses?` limit source.
- Billing (Stripe) flows and `Account::PlanUsageAndLimits`.
- Reports v2 query logic and rollup correctness.
- Search: Searchkick/OpenSearch indexing paths and GIN fallback.
- Help-center rendering and custom-domain routing details.
- Frontend: component trees, store module internals, widget ↔ SDK postMessage protocol.
- `leaves` table purpose (no model found).
- Security posture (rack-attack rules, CSP, SSRF filter usage, HMAC verification paths) — not reviewed.
- Spec coverage quality — specs not read or run.

## Static-analysis limitations

- No AST/LSP: dynamic constructs (`send(processor, …)`, `constantize`, Wisper method dispatch, `prepend_mod_with` string constants, ERB-in-YAML) resolved manually.
- Fan-in counts are by constant name only (lower bounds).
- Line numbers drift with any edit; always re-verify.

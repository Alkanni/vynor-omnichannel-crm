# Repository Inventory

Commit `9f920b54` · Phase 0–1 output (environment, capability, structure).

## Environment & capability assessment

| Item | Finding |
|---|---|
| Working dir | `/home/acgix/vynor-omnichannel-crm` (git repo, branch `main`, tree clean before analysis) |
| Size | 9,281 tracked files. By ext: 2,784 json (mostly i18n), 2,647 rb, 1,187 vue, 1,127 js, 481 yml, 372 jbuilder |
| Top dirs (files) | `app` 6,482 · `spec` 1,090 · `enterprise` 557 · `swagger` 310 · `config` 193 · `db` 182 · `public` 152 · `lib` 146 |
| Existing AI docs | `AGENTS.md` (`CLAUDE.md` is a symlink to it), `.windsurf/rules/chatwoot.md`, `docs/rails_upgrade_assessment.md`, `docs/rails_upgrades/7_2.md` |
| Ruby / Bundler | **not installed** on host → no `rails runner`, no `rspec`, no Ruby LSP |
| Node / pnpm | installed (v24.19.0) — not used (no scripts executed) |
| ripgrep | available — primary analysis tool |
| ast-grep | **missing** (`/usr/bin/sg` is util-linux `sg`, not ast-grep) |
| Serena | CLI installed (`~/.local/bin/serena`) but **not connected as an MCP server**; Ruby LSP backend would need Ruby → unused |
| CodeGraphContext / GitNexus / Repomix / ctags / cloc | missing |
| MCP servers relevant to code analysis | none connected |

**Consequence:** all relationships are from text search + reading. No call-graph tooling; dynamic dispatch (`send`, `constantize`, Wisper event names → method names, `prepend_mod_with`) was resolved by hand.

## Structure map (VERIFIED)

```
app/
  controllers/   191  Rails controllers: api/v1, api/v2, public/, platform/, super_admin/, webhooks/, devise_overrides/
  models/        112  ActiveRecord models; channel/* (12 channel types); concerns/ (41)
  services/      275  Business logic, grouped by domain/channel (whatsapp/, conversations/, messages/, ...)
  builders/       38  Object construction (MessageBuilder, ConversationBuilder, ContactInbox*Builder, v2 reports)
  jobs/           99  Sidekiq jobs (ActiveJob)
  listeners/      12  Wisper subscribers (event bus consumers)
  dispatchers/     4  Event bus (Dispatcher, SyncDispatcher, AsyncDispatcher)
  policies/       26  Pundit authorization
  finders/         6  Query objects (ConversationFinder, MessageFinder, ...)
  presenters/ drops/ mailers/ mailboxes/ fields/ dashboards/ (administrate) channels/ (ActionCable)
  views/         447  jbuilder JSON views (api/), ERB (layouts, mailers, public portal, super_admin)
  javascript/   5156  Vue apps: dashboard/ widget/ v3/ (auth) portal/ survey/ sdk/ superadmin_pages/ shared/ design-system/
enterprise/            Overlay: app/{models,services,controllers,jobs,policies,listeners,dispatchers,...}, lib/captain, config/
lib/                   Infra helpers: chatwoot_app.rb, global_config*.rb, current.rb, events/, redis/, integrations/, captain/, llm/, tasks/
config/                routes.rb (780 lines), features.yml, installation_config.yml, schedule.yml, sidekiq.yml, llm.yml, integration/apps.yml
db/                    schema.rb (98 tables), migrate/ (180 migrations, squashed at 20230426130150_init_schema.rb), seeds.rb
swagger/               OpenAPI definitions (public API docs)
spec/ tests/           RSpec (Ruby), Vitest specs live next to JS (specs/ dirs)
docker/ deployment/ .devcontainer/ clevercloud/ app.json   Deployment artefacts
```

Generated/vendored boundaries: `db/schema.rb` (generated), `app/javascript/dashboard/i18n/locale/*` and `config/locales/*` except `en` (Crowdin-managed), `pnpm-lock.yaml`, `Gemfile.lock`, `public/`.

## Technology stack (VERIFIED from Gemfile / package.json / config)

| Concern | Technology | Evidence |
|---|---|---|
| Web framework | Rails (schema 7.1), Puma | `Gemfile`, `db/schema.rb:13` |
| DB | PostgreSQL; extensions pg_stat_statements, pg_trgm, pgcrypto, plpgsql, vector | `db/schema.rb:15-19` |
| DB triggers | `hairtrigger` gem (per-account display_id sequences) | `db/schema.rb` tail, `app/models/conversation.rb:430` |
| Background jobs | Sidekiq + sidekiq-cron | `config/sidekiq.yml`, `config/schedule.yml` |
| Cache / KV | Redis via `$alfred` / `$velma` ConnectionPools (namespaced) | `config/initializers/01_redis.rb` |
| Realtime | ActionCable on Redis | `config/cable.yml`, `app/channels/room_channel.rb` |
| Event bus | Wisper (pub/sub) | `app/dispatchers/base_dispatcher.rb:2` |
| AuthN | devise, devise_token_auth, devise-two-factor, omniauth (google, saml, oauth2), access tokens | `Gemfile`, `app/controllers/application_controller.rb` |
| AuthZ | Pundit | `app/controllers/application_controller.rb:4` |
| JSON views | jbuilder | `app/views/api/**` |
| Search | pg_search / GIN trgm; optional Searchkick + OpenSearch (enterprise) | `app/models/message.rb:42`, `lib/chatwoot_app.rb:50` |
| AI / LLM | ruby-openai, ruby_llm, ai-agents, pgvector/neighbor | `Gemfile`, `config/llm.yml` |
| Storage | ActiveStorage (S3, Azure, GCS) | `config/storage.yml` |
| Email in | ActionMailbox (+ SES, IMAP polling) | `app/mailboxes/` |
| Billing | Stripe (enterprise) | `enterprise/app/services/enterprise/billing/` |
| Admin UI | administrate (Super Admin) | `app/dashboards/`, `app/controllers/super_admin/` |
| Audit | audited (enterprise `Audit` concern) | `Gemfile`, `Enterprise::Audit::*` |
| Frontend | Vue 3, Vite (vite_rails), vue-router, Vuex + Pinia, vue-i18n, Tailwind, FormKit | `app/javascript/entrypoints/dashboard.js` |
| APM (optional) | Datadog, Elastic APM, Scout, New Relic, Sentry, OpenTelemetry | `config/application.rb:11-34` |
| Package mgrs | Bundler, pnpm | `Gemfile.lock`, `pnpm-lock.yaml` |

## Process topology (VERIFIED: `Procfile`, `Procfile.dev`)

- `web`: `bin/rails server` (Puma) — HTTP API, dashboard HTML shell, ActionCable, webhooks.
- `worker`: `sidekiq -C config/sidekiq.yml` — 16 queues, strict priority order (critical → … → action_mailbox_incineration).
- `release`: `rails db:chatwoot_prepare`.
- dev adds `vite: bin/vite dev`.
- Cron (sidekiq-cron, `config/schedule.yml`): 10 entries — scheduled items every 5 min, IMAP fetch every 1 min, periodic assignment every 30 min, daily housekeeping/version check/account deletion.

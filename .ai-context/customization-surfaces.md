# Customization Surfaces

Commit `9f920b54`. Maps **where** customization is possible and what it touches. It does **not** recommend implementations.
Levels follow the brief: L1 config → L6 core architecture.

## L1 — Configuration / environment

| Surface | Location | Intentional? | Affects | Verify |
|---|---|---|---|---|
| ENV vars | `.env.example` (12.8 KB), `config/app.yml`, `config/application.rb` (APM, encryption), `config/initializers/*` | Yes | process behavior, integrations, Redis/DB, storage, mail | boot app; `ENV.fetch` sites |
| Installation configs (112) | `config/installation_config.yml` → `installation_configs` table; editable in Super Admin only if `locked: false` | Yes | install-wide behavior; cached 1 day in Redis (`lib/global_config.rb:4`) | `GlobalConfig.clear_cache`; Super Admin UI |
| Account feature flags (70) | `config/features.yml`; toggled per account in Super Admin → account edit page → Features (`AccountFeaturesField`, CE since #164; premium, `chatwoot_internal` and deprecated flags are not listed and keep their value on save), for all accounts at once in Super Admin → Settings → Account features (`SuperAdmin::AccountFeaturesController`, #166, one feature per click), or `Account#enable_features!` in a console | Yes | gated UI + backend checks | `account.feature_enabled?` |
| Sidekiq concurrency / queues | `config/sidekiq.yml` | Yes | throughput | worker logs |
| Cron schedule | `config/schedule.yml` (spec `spec/configs/schedule_spec.rb` validates it) | Yes | background cadence | spec |
| LLM providers/models | `config/llm.yml` | Yes | Captain/AI | AI features |
| Integration catalog | `config/integration/apps.yml` | Yes | integrations list UI + `Integrations::App` | integrations page |
| Enterprise toggle | `DISABLE_ENTERPRISE` env (`lib/chatwoot_app.rb:15`) | Yes | removes EE prepends | full regression |

**Constraint (VERIFIED):** feature flags are bit positions by **order** in `features.yml` (`app/models/concerns/featurable.rb:15-28`); header says "DO NOT change the order of features EVER"; new flags must use `column: feature_flags_ext_1` and be appended (`config/features.yml:1-14`).

## L2 — Branding & presentation

| Surface | Location | Intentional? | Notes |
|---|---|---|---|
| Installation branding | InstallationConfig `INSTALLATION_NAME`, `LOGO`, `LOGO_DARK`, `LOGO_THUMBNAIL`, `BRAND_NAME`, `BRAND_URL`, `WIDGET_BRAND_URL`, `TERMS_URL`, `PRIVACY_URL`, `DISPLAY_MANIFEST` (`config/installation_config.yml:17-56`) | Yes | Exposed to SPA via `window.globalConfig` (`app/controllers/dashboard_controller.rb:49-54`) |
| **Branding reset risk** | `enterprise/config/premium_installation_config.yml` + `Internal::ReconcilePlanConfigService` | — | On `community` plan, a daily production job resets these keys to Chatwoot values and disables premium features (incl. `disable_branding`). See [modules/enterprise-overlay.md](modules/enterprise-overlay.md#premium-plan-reconciliation-verified--affects-rebranding) |
| UI copy containing "Chatwoot" | `useBranding().replaceInstallationName` (`app/javascript/shared/composables/useBranding.js`) | Yes (per AGENTS.md) | 52 lines in `dashboard/i18n/locale/en/*.json`; 4 in `config/locales/en.yml` |
| Brand assets | `public/brand-assets/` (logo paths referenced by installation config defaults) | Yes | static files |
| Colors / design tokens | `tailwind.config.js`, `theme/colors.js` | Yes | global look |
| Widget appearance | `channel_web_widgets.widget_color`, `welcome_title`, `welcome_tagline`, `feature_flags` (per inbox) | Yes | per-inbox |
| Email layouts | `app/views/layouts/mailer*`, `app/views/mailers/**`; EE `branded_email_layout` (`InboxBrandedEmailLayoutable`) | Partly | |
| Help center theming | `portals` columns (color, header, custom_domain), `app/views/public/` | Yes | |
| Dashboard scripts | InstallationConfig `DASHBOARD_SCRIPTS` (`dashboard_controller.rb:54`) | Yes | inject JS into dashboard |
| Locales | `config/locales/*.yml`, `dashboard/i18n/locale/*` (Crowdin) | Yes | non-`en` are generated |

## L3 — Existing extension points & adapters

| Surface | Location | Intentional? | Dependencies |
|---|---|---|---|
| Webhooks (account & API inbox) | `Webhook` model, `WebhookListener`, `WebhookJob`, `lib/webhooks/trigger.rb` | Yes | event payloads `webhook_data` |
| Agent bots (external HTTP bots) | `AgentBot.outgoing_url`, `AgentBotListener`, `AgentBots::WebhookJob`; bot API token allow-list `AccessTokenAuthHelper::BOT_ACCESSIBLE_ENDPOINTS` | Yes | conversation `pending` status semantics |
| Integration hooks | `Integrations::Hook` + `HookJob::INTEGRATION_PROCESSORS` (`app/jobs/hook_job.rb:6-12`) + `config/integration/apps.yml` | Yes | adding a processor requires code |
| Dashboard apps (iframe apps in conversation sidebar) | `DashboardApp` model / settings | Yes | |
| Platform API | `/platform/api/v1` + `PlatformApp` permissibles | Yes | provisioning accounts/users externally |
| Public client API | `/public/api/v1/inboxes/...` | Yes | custom chat frontends |
| API channel | `Channel::Api` (webhook_url, HMAC) | Yes | build arbitrary channels outside the app |
| Automation rules / macros | DB-configured | Yes | `AutomationRules::ActionService`, `ActionService` |
| Custom attributes | `custom_attribute_definitions` + jsonb `custom_attributes` | Yes | filters, reports |
| Channel adapter pattern | `Base::SendOnChannelService`, `SendReplyJob::CHANNEL_SERVICES` | Code-level pattern | see [flows/outbound-reply.md](flows/outbound-reply.md) |
| Event listeners | `AsyncDispatcher#listeners` / `SyncDispatcher#listeners` (prependable) | Code-level, used by EE | see [flows/event-bus.md](flows/event-bus.md) |
| `prepend_mod_with` / `custom/` slot | `config/initializers/01_inject_enterprise_edition_module.rb`, `lib/chatwoot_app.rb:32-48` | Yes for EE; `custom/` slot exists but **not on load paths** | [modules/enterprise-overlay.md](modules/enterprise-overlay.md) |
| LLM provider abstraction | `lib/llm/*`, `config/llm.yml`, ruby_llm | Yes | Captain |

## L4 — New isolated modules / features

Typical shape (INFERRED from existing modules): model + migration, controller under `api/v1/accounts/`, policy, jbuilder views, Vuex/Pinia store + API client, route under `routes/dashboard/...`, feature flag appended to `features.yml`, i18n in `en.json`/`en.yml`, optional listener for events. Isolated enough if it only **consumes** events and reads core models.

## L5 — Shared contracts / database changes

| Contract | Where consumed | Impact |
|---|---|---|
| Event names & payload (`lib/events/types.rb`, `push_event_data`, `webhook_data`) | ActionCable frontend, external webhooks, agent bots, integrations | external consumers break silently |
| REST JSON (jbuilder) | dashboard, widget, mobile apps (`.well-known` app links suggest iOS/Android apps), API users, `swagger/` | versioning is only v1/v2 by path |
| Core tables (`conversations`, `messages`, `contacts`, `inboxes`) | everywhere; GIN/trigram indexes; triggers | migrations on large tables; `messages` is the biggest (INFERRED) |
| Enum integer values (`Conversation.status`, `Message.message_type/content_type/status`, `AccountUser.role`) | DB, frontend constants, webhooks | reordering breaks data |
| Feature flag bit order | `accounts.feature_flags*` | reordering flips flags for all accounts |

## L6 — Core architectural modifications

- Model-callback-driven side effects in `Message` / `Conversation` (changing order or moving to services affects every channel and listener).
- Dispatcher sync/async split (`app/dispatchers/dispatcher.rb`).
- Tenancy model (`account_id` scoping, `Current`).
- Enterprise injection mechanism.
- Frontend state migration Vuex → Pinia (in progress upstream).

Every L5–L6 change also creates **upstream merge friction**: the fork is currently identical to upstream, so the cheapest customizations to maintain are L1–L3 and isolated L4 code.

# System Overview

Commit `9f920b54`.

## One-paragraph summary (VERIFIED)

An omnichannel customer-support platform. **Channels** (web widget, email, WhatsApp, Facebook, Instagram, TikTok, Telegram, LINE, Twilio SMS, generic SMS, Twitter, API) feed **incoming messages** into multi-tenant **Accounts**. Each channel is wrapped by an **Inbox**; a customer is a **Contact** linked to an inbox via **ContactInbox**; messages live in **Conversations**. Agents (Users) reply from a Vue dashboard; replies are pushed back to the originating channel by background jobs. Every significant model change emits an **event** on an in-process bus (Wisper) that fans out to realtime (ActionCable), webhooks, notifications, automations, agent bots, integrations, reporting and (enterprise) the **Captain** AI agent.

## Runtime diagram

```mermaid
flowchart LR
  subgraph Clients
    D[Dashboard SPA<br/>app/javascript/dashboard]
    W[Web widget iframe<br/>app/javascript/widget + sdk]
    P[Help-center portal<br/>/hc/:slug]
    X[External channels<br/>Meta, Twilio, Telegram, LINE, TikTok, email]
    API[3rd-party API clients<br/>api_access_token]
  end

  subgraph Web[Puma: Rails web]
    C[Controllers<br/>api/v1, api/v2, widget, public, platform, webhooks]
    M[Models + callbacks]
    DISP[Dispatcher<br/>SyncDispatcher]
    AC[ActionCable RoomChannel]
  end

  subgraph Worker[Sidekiq worker]
    EDJ[EventDispatcherJob<br/>AsyncDispatcher listeners]
    JOBS[SendReplyJob, WebhookJob, HookJob,<br/>ActionCableBroadcastJob, channel *EventsJob, Captain jobs]
    CRON[sidekiq-cron schedule.yml]
  end

  PG[(PostgreSQL)]
  R[(Redis: cache, cable, sidekiq,<br/>$alfred, $velma)]

  D -- REST JSON --> C
  W -- REST + X-Auth-Token --> C
  API --> C
  X -- webhooks --> C
  P --> C
  C --> M --> PG
  M -- after_commit dispatch --> DISP
  DISP -- sync listeners --> AC
  DISP -- enqueue --> EDJ
  EDJ --> JOBS
  JOBS -- send reply --> X
  JOBS --> AC
  AC -- websocket --> D
  AC -- websocket --> W
  CRON --> JOBS
  Web & Worker --- R
```

## Architectural classification (VERIFIED unless noted)

| Pattern | Evidence |
|---|---|
| **Modular monolith** (single Rails app, single DB) | One `config/application.rb`, one `db/schema.rb`; no service boundaries |
| **Layered MVC + service objects** | Controllers → Builders/Services (`pattr_initialize` POROs) → Models; jbuilder views |
| **Event-driven internals** | `Rails.configuration.dispatcher` (Wisper) with sync + async listeners (`app/dispatchers/*`) |
| **Multi-tenant by row** (`account_id` on nearly every table) | `db/schema.rb`; `EnsureCurrentAccountHelper` scoping |
| **Open-core overlay** | `enterprise/` modules prepended into OSS classes (`config/initializers/01_inject_enterprise_edition_module.rb`) |
| **Polymorphic channel adapter** | `Inbox belongs_to :channel, polymorphic: true` (`app/models/inbox.rb:62`); per-channel `SendOn*Service` (`app/jobs/send_reply_job.rb:4-16`) |
| Not hexagonal / not microservices | No ports/adapters layer; models call services and vice-versa (INFERRED from callback code) |

## Main application surfaces

| Surface | Mount | Auth | Frontend |
|---|---|---|---|
| Agent dashboard | `/app/*` → `DashboardController#index` | devise_token_auth headers | `entrypoints/dashboard.js` |
| Auth pages (login/signup/reset) | `/app/login` etc. | — | `entrypoints/v3app.js` (`app/javascript/v3`) |
| Account API | `/api/v1/accounts/:account_id/*` | user token or `api_access_token` | — |
| Widget API | `/api/v1/widget/*` | `website_token` + `X-Auth-Token` JWT | `entrypoints/widget.js`, `entrypoints/sdk.js` |
| Public client API | `/public/api/v1/inboxes/*` | inbox identifier | — |
| Platform API | `/platform/api/v1/*` | PlatformApp access token + permissibles | — |
| Help center | `/hc/:slug/*` | public | `entrypoints/portal.js` |
| Super Admin | `/super_admin/*` (+ `/monitoring/sidekiq`) | devise `SuperAdmin` | administrate + `superadmin.js` |
| Channel webhooks | `/webhooks/*`, `/bot`, `/twilio/*` | per-provider signatures | — |
| Enterprise API | `/enterprise/api/v1/*`, Stripe/Firecrawl webhooks | as above | — |

See [api-map.md](api-map.md) for detail.

# Change Impact Guide

Commit `9f920b54`. Use before editing. Each row: what else to check when you change X. Derived from verified relationships in the other docs; impacts marked INFERRED where not traced.

## Pre-change checklist (all changes)

1. `git rev-parse HEAD` vs `9f920b54` — if different, re-verify cited lines.
2. Search both trees: `rg -n "ClassName|method_name" app enterprise lib spec`.
3. Check for an EE prepend at the bottom of the file (`prepend_mod_with`) and the matching `enterprise/app/**/enterprise/...` module — EE may override the method you change (`super` chains).
4. Check for `include_mod_with('Concerns::X')` → `enterprise/app/models/enterprise/concerns/x.rb`.
5. If the change touches a model callback, enumerate events it dispatches and the listeners in [flows/event-bus.md](flows/event-bus.md).
6. If it touches serialized output, check jbuilder **and** `push_event_data` **and** `webhook_data`.
7. Specs: `spec/<same path>_spec.rb` and `spec/enterprise/...`.

## Hotspots

| If you change… | Also impacts | Verify with |
|---|---|---|
| `Message` callbacks (`app/models/message.rb:66-141, 324-460`) | outbound delivery (all channels), realtime, webhooks, automations, agent bots, Captain, reporting (first reply, waiting_since), notifications, search index | `spec/models/message_spec.rb`, listener specs, channel send specs |
| `Conversation` callbacks / `list_of_keys` (`app/models/conversation.rb:136-147, 268-393`) | `conversation.updated` webhook volume, ActionCable updates, automation triggers, assignment, unread counts, SLA (EE), Captain outcome tracking | `spec/models/conversation_spec.rb`, `spec/listeners/*` |
| `Conversation.status` / enum values | frontend filters, reports, auto-resolve, Captain (`pending`), bot handoff, DB data | grep `open?\|pending?\|resolved?\|snoozed?` |
| `MessageBuilder` (`app/builders/messages/message_builder.rb`) | dashboard replies, API channel inbound, bots via API, EE prepend `Enterprise::Messages::MessageBuilder` | builder spec, messages controller spec |
| `SendReplyJob` / `Base::SendOnChannelService` | every outbound channel; echo-loop prevention | each `spec/services/<channel>/send_on_*_spec.rb` |
| `ContactInboxWithContactBuilder` / `ContactInboxBuilder` | contact dedupe for every inbound channel; EE prepend on `ContactInboxBuilder` | builder specs |
| `Dispatcher` / listener lists | all side effects; EE `Enterprise::{Sync,Async}Dispatcher` uses `super +` | listener specs |
| Event payload methods (`push_event_data`, `webhook_data`, `Conversations::EventDataPresenter`) | dashboard realtime store, widget, external webhooks, bots, mobile apps (INFERRED) | ActionCable listener spec, webhook listener spec |
| jbuilder views `app/views/api/**` (and EE `enterprise/app/views`) | dashboard, widget, mobile apps, Swagger docs | request specs; update `swagger/` |
| Auth concerns (`access_token_auth_helper.rb`, `ensure_current_account_helper.rb`, `website_token_helper.rb`) | every API request; tenancy isolation (security-critical) | request specs; security review |
| Pundit policies | access control; EE prepends for 8 policies | policy specs incl. `spec/enterprise` |
| `config/features.yml` | account flags bitfield — **append only**, `column: feature_flags_ext_1` | `spec/models/concerns/featurable*`; frontend `featureFlags.js` |
| `config/installation_config.yml` | seeded configs, Super Admin UI, `GlobalConfig` cache (1 day), premium reconciliation (EE) | `ConfigLoader` (`lib/config_loader.rb`) behavior |
| DB migration on `messages`/`conversations`/`contacts` | large tables, GIN/trigram indexes, triggers on `conversations` | migration timing; `db/schema.rb` regenerate |
| Adding an event | `lib/events/types.rb`, listeners, `Webhook` allowed subscriptions, frontend `actionCable.js` | — |
| Redis keys (`lib/redis/redis_keys.rb`, `Redis::Alfred`) | presence, round robin, locks, unread counts; cleanup job `Internal::RemoveStaleRedisKeysJob` | — |
| Sidekiq queue names | `config/sidekiq.yml` order; job `queue_as` | worker config |
| Branding strings | `en.json`/`en.yml` only (Crowdin for others); `replaceInstallationName`; EE premium reset | i18n spec `vitest.i18n.js` (INFERRED purpose) |
| Anything in `enterprise/` | separate license; upstream merge conflicts | — |

## Upstream-merge impact (fork-specific)

The fork has no divergence yet (`git log` all upstream). Every edited upstream file becomes a future merge-conflict site when pulling `upstream/main`. Prefer additive files (new listeners, new services, new routes in separate namespaces, new Vue routes) over editing hotspots above.

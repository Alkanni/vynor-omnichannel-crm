# API Map

Commit `9f920b54`. Source: `config/routes.rb` (780 lines). Controllers mirror route namespaces under `app/controllers/` (and `enterprise/app/controllers/` for EE). JSON rendered by jbuilder in `app/views/api/**` (EE overrides in `enterprise/app/views`). OpenAPI docs: `swagger/` (served at `/swagger`, `config/routes.rb:774-775`).

## Surfaces

| Namespace | Routes (lines) | Base controller | Auth |
|---|---|---|---|
| `/auth/*` (devise_token_auth) | 3-11 | `DeviseOverrides::*` | email/password, returns token headers |
| `/app/*` (SPA shell) | 19-32 | `DashboardController` | HTML; SPA handles auth |
| `/api/v1/accounts/:account_id/*` | 48-466 | `Api::V1::Accounts::BaseController` | user token or `api_access_token` (+ `api_and_webhooks` flag) |
| `/api/v1/profile`, `/api/v1/notification_subscriptions` | 474-494 | `Api::V1::ProfilesController` etc. | user |
| `/api/v1/integrations/webhooks` | 467-469 | — | integration callbacks |
| `/api/v1/widget/*` | 496-528 | `Api::V1::Widget::BaseController` | `website_token` + `X-Auth-Token` |
| `/api/v2/accounts/*` | 530-570 | `Api::V2::*` | reports v2, account signup (INFERRED) |
| `/enterprise/api/v1/*`, `/enterprise/webhooks/{stripe,firecrawl}` | 573-595 | EE controllers | user / provider signature |
| `/platform/api/v1/{users,agent_bots,accounts}` | 598-622 | `PlatformController` | PlatformApp token + permissibles |
| `/public/api/v1/inboxes/:inbox_id/contacts/...`, `csat_survey` | 624-646 | `PublicController` | inbox identifier + contact source_id |
| `/hc/:slug/*` help center | 648-659 | `Public::Api::V1::Portals::*` | public; custom domains |
| `/webhooks/*`, `/bot`, `/twilio/*` channel ingress | 671-705 | `Webhooks::*`, `Twilio::*` | provider signatures/tokens |
| OAuth callbacks `/{microsoft,google,instagram,tiktok,notion}/callback`, `/twitter|linear|shopify/callback` | 684-712 | `*::CallbacksController` | OAuth state |
| `.well-known/*` | 715-718 | — | public |
| `/super_admin/*`, `/monitoring/sidekiq` | 725-765 | `SuperAdmin::*` (administrate) | devise `super_admin` |
| `/installation/onboarding` | 767-770 | `Installation::OnboardingController` | first-run |
| `/health`, `/api` | 41-43 | `HealthController`, `ApiController` | public |

## Account-scoped resources (`config/routes.rb` 54-466)

actions (contact merge), bulk_actions, onboarding, agents, captain (EE: assistants, documents, scenarios, inboxes, copilot, tasks…), saml_settings, agent_bots, contact_inboxes, assignable_agents, audit_logs, callbacks, canned_responses, automation_rules, macros, sla_policies, custom_roles, agent_capacity_policies, campaigns (+ `analytics/metrics`, `analytics/contacts` per campaign, #160), dashboard_apps, channels, **conversations** (messages, assignments, labels, participants, direct_uploads, toggle_status/priority/typing, …), search, companies, **contacts** (conversations, labels, notes, contact_inboxes, filter, import/export…), data_imports, csat_survey_responses, applied_slas, reporting_events, custom_attribute_definitions, custom_filters, branded_email_layout, **inboxes** (members, agent_bot, health…), inbox_members, labels, notifications, notification_settings, teams, assignment_policies, OAuth sub-namespaces (twitter, microsoft, google, instagram, tiktok, notion, whatsapp), webhooks, integrations (apps, hooks, slack, dyte, linear, shopify, notion…), portals (categories, articles), upload.

Extracted with `sed -n 54,466p config/routes.rb | grep -oE "^ {10}(resources?|namespace) :[a-z_]+"`.

## Key controller entry points

| Endpoint | Controller#action | Downstream |
|---|---|---|
| `POST …/conversations/:id/messages` | `Api::V1::Accounts::Conversations::MessagesController#create` | `Messages::MessageBuilder` |
| `POST …/conversations` | `Api::V1::Accounts::ConversationsController#create` (EE-prepended) | `ConversationBuilder` (`conversations_controller.rb:42`) |
| `GET …/conversations` | `ConversationsController#index` | `ConversationFinder` (EE-prepended) |
| `POST …/conversations/:id/toggle_status` | `ConversationsController#toggle_status` | model status change → events |
| `POST …/conversations/:id/assignments` | `Conversations::AssignmentsController` | `Conversations::AssignmentService` (EE-prepended) |
| `POST /api/v1/widget/messages` | `Api::V1::Widget::MessagesController#create` | `Message.save!` |
| `POST /webhooks/whatsapp/:phone` | `Webhooks::WhatsappController#process_payload` | `Webhooks::WhatsappEventsJob` |
| `GET/PATCH …/bookings` (fork, #178) | `Api::V1::Accounts::BookingsController#index/#update` | `BookingPolicy` (feature `bookings`, conversation access), `Booking#change_status!` |

## Response rendering

- Default: implicit jbuilder template matching action (e.g. `app/views/api/v1/accounts/conversations/messages/create.json.jbuilder`, VERIFIED exists).
- Push/Webhook payloads are **not** jbuilder: they come from model methods `push_event_data`, `webhook_data` (`PushDataHelper` concern; `Conversations::EventDataPresenter`, EE-prepended). Changing serializers must consider all three: jbuilder views, `push_event_data`, `webhook_data`.

## Frontend API clients

`app/javascript/dashboard/api/*.js` (one class per resource; `ApiClient` base builds URLs). Enterprise clients pass `{ enterprise: true }` → `/enterprise/api/v1`. Widget clients: `app/javascript/widget/api/*.js`.

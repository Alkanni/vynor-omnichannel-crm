# Module: Enterprise Overlay (`enterprise/`) & `custom/` Extension Slot

Commit `9f920b54`. Status: **VERIFIED** mechanism; individual EE modules only sampled.

## Licensing (VERIFIED)

`enterprise/LICENSE` is the **Chatwoot Enterprise License** (Copyright Chatwoot Inc), distinct from the MIT `LICENSE` at the root. Modifying or commercially using `enterprise/` code is governed by that license — a legal, not technical, constraint for this fork. Setting `DISABLE_ENTERPRISE=true` makes `ChatwootApp.enterprise?` false (`lib/chatwoot_app.rb:14-18`), which disables module injection, but `enterprise/app/**` remains on the eager-load path (`config/application.rb:42-46`) — so EE classes still load; only the prepends stop (INFERRED from code; not runtime-tested).

## Loading mechanism (VERIFIED)

1. `config/application.rb:42-50` — eager-load `enterprise/lib`, `enterprise/listeners` (line 44 — **this directory does not exist**; EE listeners actually live in `enterprise/app/listeners`, loaded via the `enterprise/app/**` glob), every `enterprise/app/*` dir; prepend `enterprise/app/views` to view paths; require `enterprise/config/initializers/**/*.rb` (currently `omniauth_saml.rb`).
2. `config/initializers/01_inject_enterprise_edition_module.rb` — `Module.prepend(InjectEnterpriseEditionModule)` giving every class `prepend_mod_with(name)`, `include_mod_with`, `extend_mod_with`.
3. `each_extension_for` iterates `ChatwootApp.extensions` (`%w[enterprise]`, or `%w[enterprise custom]` if `custom/` exists) and looks up `Enterprise::<Name>` / `Custom::<Name>`; if defined, it is prepended/included.
4. OSS files end with e.g. `Conversation.prepend_mod_with('Conversation')` + `Conversation.include_mod_with('Concerns::Conversation')` (`app/models/conversation.rb:434-436`).

## Injection points: 109 total (80 prepend, 29 include)

By area: models 39 · controllers 24 · services 15 · policies 8 · jobs 7 · lib/captain 3 · builders 3 · presenters 2 · finders 2 · dispatchers 2 · mailers 1 · listeners 1 · actions 1 · `lib/chatwoot_hub.rb` 1.
Regenerate: `rg -n "(prepend|include|extend)_mod_with\('[^']+'" app lib -o`.

Notable namespaced targets: `Api::V1::Accounts::{Agents,Contacts,Conversations,Conversations::Messages,Inboxes,Portals,CsatSurveyResponses,Onboardings,...}Controller`, `Api::V1::AccountsSettings`, `DeviseOverrides::{Sessions,Passwords,OmniauthCallbacks}Controller`, `SuperAdmin::{Accounts,AppConfigs}Controller`, `AutoAssignment::AssignmentService`, `Conversations::{AssignmentService,PermissionFilterService,EventDataPresenter}`, `Messages::MessageBuilder`, `MessageTemplates::HookExecutionService`, `Whatsapp::{IncomingMessageBaseService,Providers::BaseService,Providers::WhatsappCloudService,OneoffCampaignService}`, `Internal::{CheckNewVersionsJob,TriggerDailyScheduledItemsJob,TriggerHourlyScheduledItemsJob}`, `Account::PlanUsageAndLimits`, `Channel::{Whatsapp,TwilioSms}`, `Captain::{BaseTaskService,ReplySuggestionService}`, `AsyncDispatcher`, `SyncDispatcher`, `ActionCableListener`.

`include_mod_with('Concerns::<Model>')` used for: Account, AccountUser, Article, AssignmentPolicy, Attachment, Contact, Conversation, CustomAttributeDefinition, Inbox, Message, Portal, User, ApplicationController. `include_mod_with('Audit::<Model>')` adds audit logging to 12 models.

## EE feature areas

| Area | Paths |
|---|---|
| Captain AI | see [flows/captain-ai-response.md](../flows/captain-ai-response.md) |
| Billing / plans (Stripe) | `enterprise/app/services/enterprise/billing/`, `Account::PlanUsageAndLimits`, `/enterprise/webhooks/stripe` |
| SLA | `SlaPolicy`, `AppliedSla`, `SlaEvent`, `enterprise/app/jobs/sla/` |
| Custom roles | `CustomRole`, `Enterprise::AccountUser#permissions`, `enterprise/app/policies/enterprise/*` |
| Audit logs | `Enterprise::AuditLog`, `Enterprise::Audit::*` |
| SAML SSO | `AccountSamlSettings`, `enterprise/config/initializers/omniauth_saml.rb` |
| Voice / calls | `Call`, `enterprise/app/services/voice/`, Twilio voice routes `config/routes.rb:700-705` |
| Companies (CRM) | `Company`, `Enterprise::Concerns::Contact` |
| Capacity-based assignment | `AgentCapacityPolicy`, `InboxCapacityLimit`, `Enterprise::AutoAssignment::*` |
| Advanced search | `Enterprise::SearchService`, Searchkick/OpenSearch |

## Premium plan reconciliation (VERIFIED — affects rebranding)

Daily (production only) `Internal::CheckNewVersionsJob` → EE prepend `Enterprise::Internal::CheckNewVersionsJob#perform` (`enterprise/app/jobs/enterprise/internal/check_new_versions_job.rb:2-6`):
1. Calls Chatwoot Hub, stores `INSTALLATION_PRICING_PLAN` etc.
2. `Internal::ReconcilePlanConfigService#perform` (`enterprise/app/services/internal/reconcile_plan_config_service.rb:2-10`): if plan is `community`, **resets** every config in `enterprise/config/premium_installation_config.yml` (INSTALLATION_NAME, LOGO*, BRAND_NAME, BRAND_URL, WIDGET_BRAND_URL, …) to Chatwoot defaults and **disables** `enterprise/config/premium_features.yml` features (`disable_branding, audit_logs, sla, custom_roles, captain_integration, captain_integration_v2, captain_document_auto_sync, csat_review_notes, conversation_required_attributes`) on every account.

⇒ On a self-hosted community install, branding changes made via Super Admin installation configs are reverted daily. See [customization-surfaces.md](../customization-surfaces.md).

## `custom/` extension slot (VERIFIED partial / INFERRED gap)

`ChatwootApp.custom?` checks for a root `custom/` dir (`lib/chatwoot_app.rb:32-34`) and adds `custom` to `extensions`, so `prepend_mod_with('X')` would also look up `Custom::X`. **However** no `custom/` path is added to autoload/eager-load paths in `config/application.rb` (only `enterprise/*`). A fork using this slot would need to add `custom/app/**` (and views/initializers) to load paths. Only other reference: `app/controllers/super_admin/instance_statuses_controller.rb:15`. Not runtime-verified.

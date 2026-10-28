# Module: Frontend (Vue 3 / Vite)

Commit `9f920b54`. Status: **VERIFIED** structure; component internals not analyzed.

## Entrypoints (`app/javascript/entrypoints/`)

| File | App | Root dir |
|---|---|---|
| `dashboard.js` | Agent dashboard SPA | `app/javascript/dashboard` |
| `v3app.js` | Auth pages (login, SAML, signup, reset, confirmation) | `app/javascript/v3` (`v3/views/routes.js`) |
| `widget.js` | Chat widget (runs inside iframe) | `app/javascript/widget` |
| `sdk.js` | Host-page loader that injects the widget iframe (`window.chatwootSDK`, INFERRED) | `app/javascript/sdk` (`IFrameHelper.js`) |
| `portal.js` | Public help-center pages | `app/javascript/portal` |
| `survey.js` | CSAT survey page | `app/javascript/survey` |
| `superadmin.js`, `superadmin_pages.js` | Super Admin enhancements | `app/javascript/superadmin_pages` |

Build: `vite.config.ts` + `vite.shared.ts`; SDK lib build `vite.lib.config.ts` (`pnpm build:sdk`). Size budgets in `package.json` `size-limit` (widget 300 KB, sdk 40 KB).

## Dashboard internals (`app/javascript/dashboard/`)

| Concern | Location |
|---|---|
| Bootstrap | `entrypoints/dashboard.js:37-51` — vue-i18n, Vuex `store`, Pinia, router, FormKit, FloatingVue, Sentry |
| Routing | `routes/index.js`, `routes/dashboard/dashboard.routes.js`; feature folders under `routes/dashboard/{conversation,contacts,inbox,settings,captain,helpcenter,campaigns,companies,calls,...}` |
| Settings pages | `routes/dashboard/settings/{account,agents,inbox,teams,labels,automation,macros,integrations,captain,sla,customRoles,billing,auditlogs,security,...}` |
| State (legacy, main) | Vuex `store/index.js` + `store/modules/*` (~45 modules) |
| State (new) | Pinia `stores/{calls,callHistory,companies}.js` |
| HTTP | `api/ApiClient.js` (+ `CacheEnabledApiClient.js`), one file per resource; `api/enterprise/`, `api/captain/`, `api/channel/` |
| Realtime | `helper/actionCable.js` → `ActionCableConnector` maps server event names (`message.created`, …) to store actions |
| Components | `components-next/` (new design system; use for new work, esp. message bubbles per `AGENTS.md`); `components/` legacy |
| Feature flags | `featureFlags.js` (`FEATURE_FLAGS` constants mirroring `config/features.yml`) |
| i18n | `i18n/locale/en/*.json` (source); other locales Crowdin-managed |
| Global config | server injects `window.globalConfig` (`app/views/layouts/vueapp.html.erb:64`) from `DashboardController#set_global_config` (`app/controllers/dashboard_controller.rb:49-54`, keys LOGO, LOGO_DARK, LOGO_THUMBNAIL, INSTALLATION_NAME, BRAND_URL, BRAND_NAME, WIDGET_BRAND_URL, …); read by `shared/store/globalConfig.js` |
| Branding helper | `shared/composables/useBranding.js` `replaceInstallationName` (regex-replaces "chatwoot" with installation name) |
| Design tokens | `tailwind.config.js`, `theme/colors.js`, `theme/icons.js` |

## Conventions (from `AGENTS.md`)

Composition API `<script setup>`, Tailwind only (no custom/scoped CSS), PascalCase components, no bare strings (i18n), only edit `en.json` / `en.yml`.

## Brand-string footprint (VERIFIED counts)

`grep -rn Chatwoot app/javascript/dashboard/i18n/locale/en/*.json` → 52 lines; `config/locales/en.yml` → 4 lines. Additional hardcoded references likely in widget, mailer views, public assets (`public/brand-assets/`) — not exhaustively counted.

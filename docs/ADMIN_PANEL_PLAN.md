# Admin panel: settings regroup + redesign plan

Status: proposal (2026-11-13). Scope: `frontend/src/routes/admin/**`,
`frontend/src/lib/components/admin/**`, `frontend/src/lib/admin-nav.ts`, and the
`/api/v1/admin/settings` endpoint in `admin_controller.ex`.

## 1. What exists today

**Size.** 31 route files + 13 admin components, about 22k lines. Seven nav
sections, 25 items (`lib/admin-nav.ts`). Every page carries its own CSS (`.page-title`
is defined 20 times, `.section-title` 9 times). No admin string goes through i18n
(0 of 44 files use `$t`).

**Settings coverage is the real problem.** The backend reads about 200 DB-backed
keys through `Config.get`. The admin UI exposes roughly 35 of them. Everything else
can only be changed in SQL, which contradicts the "all tunables are admin-configurable"
rule. Examples with no UI at all: `federation_enabled`, `require_email_confirmation`,
`default_timeline_algorithm`, `media_proxy_enabled`, `storage_backend`,
`search_backend`, all `rate_limit_*`, all `max_*` content limits, all `explore_trending_*`,
`trust_gate_*`, `post_expiry_*`, `clamav_*`, `mrf_*`, payment gateway keys.

**Settings that do have UI are scattered by accident of history:**

| Setting | Lives on | Problem |
|---|---|---|
| `registration_mode`, captcha, PoW | Instance > Registration & invites (URL under `/user-management/`) | URL and nav section disagree |
| `takedown_retention_days`, `takedown_purge_enabled` | Moderation > Takedowns | retention is split across 4 pages |
| `federation_delivery_retention_days` | Federation > Delivery tab | same |
| `report_email_notifications_enabled`, `report_email_throttle_seconds` | System > Email | a moderation behaviour hidden in mail transport |
| `moderation_email_throttle_seconds` | nowhere | a second, overlapping throttle (`staff_email.ex`) |
| Posting limits, Verification tiers | Content (URL under `/user-management/`) | limits sit next to emoji catalogs |
| `instance_name`/`description` | General (Theme used to own them) | fine now, keep |

**Security gaps found during the scan** (fix first, they shape the design):

1. `GET /admin/settings` hides secrets with a *denylist* (`@hidden_settings`). Not on it:
   `stripe_secret_key`, `stripe_webhook_secret`, `paypal_secret`, `crypto_api_key`,
   `crypto_webhook_secret`, `r2_secret_key`, `r2_access_key`, `meilisearch_api_key`,
   `translation_api_key`, `giphy_api_key`, `sms_api_key`. Anyone with `settings.view`
   can read them.
2. `PUT /admin/settings` writes **any** key, untyped, and logs the raw value to the audit
   log (`Moderation.log(..., %{value: value})`). Secrets set through it land in plaintext
   in `audit_log`.
3. No type or range validation: `"5"` vs `5` vs `true` is up to each client.

## 2. Foundation: a settings registry (backend-authoritative)

One module, `Hybridsocial.Config.Registry`, declares every tunable once:

```elixir
%{key: "max_post_length_free", group: :posting, section: :limits,
  type: :integer, default: 5000, min: 1, max: 100_000, unit: :chars,
  secret: false, label_key: "admin.settings.max_post_length_free",
  help_key: "admin.settings.max_post_length_free.help"}
```

It gives us, for free:

- **Allowlist writes**: `PUT` rejects unknown keys and casts/validates by `type`/`min`/`max`.
  Fixes gap 2 and 3 and ends the "send the right JSON type" footgun.
- **Secret handling**: `secret: true` values are never returned (only `set: true/false`),
  are write-only in the UI, and are redacted in the audit log. Fixes gap 1.
- **Defaults in one place**: today defaults are repeated in every `Config.get(key, default)`.
  The registry becomes the source; `Config.get/1` falls back to it.
- **Generated UI**: `GET /admin/settings/schema` returns groups/sections/fields; the frontend
  renders them with one generic form. A new tunable becomes visible by adding one registry
  line, so coverage can't drift again.
- **"Changed from default"** and **per-setting reset**, because default is known.
- A CI test asserting every literal `Config.get("x"...)` key exists in the registry.

Bespoke editors stay bespoke where a form isn't enough: Theme, Tier matrix, Posting
limits per window, Rules, Site pages, Email templates, Relays, Policies. They just move
into the new information architecture.

## 3. New information architecture

Rule of thumb that makes it memorable: **the sidebar has two halves. Top half = things
you act on (queues, people, peers). Bottom half = Settings, and every setting lives in
exactly one Settings page named after what it governs.** Retention is one page, rate
limits are one page, all third-party keys are one page.

### Operate (daily)

| Section | Pages | Notes |
|---|---|---|
| **Home** | Dashboard, Analytics | Dashboard leads with "needs attention" counts |
| **Moderation** | Inbox (reports + auto-flag queue), Verifications, Appeals, Takedowns, Blocklists | Blocklists = IP, email domains, media hashes, hashtags, content filters (today tabs inside Moderation) |
| **People** | Users, Approvals, Invites, Staff & roles, Badges | Invites move out of the Registration settings page; it's an action list, not config |
| **Federation** | Instances, Policies & MRF lists, Delivery, Relays | operational views only; federation *settings* move to Settings |
| **Content** | Announcements, Custom emojis, Premium reactions, Site pages, Rules | the things members see, edited as content |
| **Records** | Audit log, Backups, Service health | `ServicePanel` gets its own page instead of living on the dashboard |

### Settings (`/admin/settings/<group>`, rendered from the registry)

| Group | Contains (keys) |
|---|---|
| **General** | `instance_name`, `instance_short_description`, `instance_description`, `instance_languages`, `contact_email`, `contact_account_handle`, `source_url`, `instance_thumbnail`, `instance_background_image`, `instance_og_image*` |
| **Branding & theme** | Theme editor (all `theme_*`, logos, favicon, dark palette), `app_icon_source`, mobile app links `app_*_url`, `app_banner_enabled`, `email_logo_url` |
| **Sign-up & access** | `registration_mode`, `require_email_confirmation`, captcha (`captcha_provider`, site/secret keys, `recaptcha_min_score`), PoW (`pow_enabled`, `pow_difficulty`), `reserved_handles`, `public_timeline_access`, `password_reset_ttl_seconds`, `oauth_app_token_ttl_days` |
| **Posting & accounts** | `max_post_length_*`, `characters_reserved_per_url`, `max_media_per_post`, polls (`max/min_poll_*`), profile (`max_profile_fields`, `max_field_*`, `max_featured_tags`), pins (`max_pinned_*`), subaccounts (`max_bots/groups/organizations_per_user`, `bot_posts_per_hour`), timed posts (`post_expiry_*`), DMs (`dm_edit_window_seconds`, `group_dm_max_participants`), trust (`trust_gate_links`, `trust_gate_dms`, `trust_sweep_interval_minutes`), link to Posting limits editor |
| **Media & storage** | upload sizes (`max_*_size*`, `max_upload_payload_bytes`), `image_matrix_limit`, `video_matrix_limit`, `video_frame_rate_limit`, `streams_min_duration_seconds`, `storage_backend` + S3/R2, media proxy (`media_proxy_*`), antivirus (`clamav_*`, `infected_upload_*`), `upload_filters` |
| **Feeds & discovery** | `default_timeline_algorithm`, `feed_collapse_author_runs_after`, global prewarm (`global_feed_prewarm_*`), trending tags (`trending_hashtag_*`), Explore trending (`explore_trending_*`), `streams_trending_decay_seconds`, search (`search_backend`, `meilisearch_*`) |
| **Federation** | `federation_enabled`, `federation_key_cache_seconds`, `federation_retry_window_hours`, dead actors (`federation_dead_actor_*`), MRF (`mrf_policies`, `mrf_keyword_*`, `mrf_hellthread_threshold`, `mrf_activity_expiration_days`), `instance_actor_legacy_usernames` |
| **Moderation & safety** | report emails (`report_email_notifications_enabled`, merge the two throttles into one), `group_report_escalation_hours`, `content_filter_engine`, `content_filter_webhook_url`, `takedown_purge_enabled`, `takedown_reminder_lead_days` |
| **Rate limits** | every `rate_limit_*` (authenticated, anonymous, federation, login, register, 2FA, OAuth token, password reset, recover, resend confirmation, app registration) |
| **Monetization** | `tiers_enabled`, tier prices, `subscription_currency`, `payment_gateway` + Stripe/PayPal/crypto keys, premium short handles, `ads_enabled`, link to Tier limits editor |
| **Integrations** | Email delivery (provider/SMTP/Resend + templates), Translation, Webhooks, SMS, Analytics provider, Giphy, push (`vapid_*`, `notification_channels`). Each integration is a card with a status pill: Connected / Not configured / Error |
| **Data retention** | every `*_retention_days` in one table: reports, appeals, takedowns, federation deliveries, metrics, backups |

Old URLs (`/admin/user-management/registration`, `/admin/theme`, …) redirect to their new
home so bookmarks keep working.

## 4. Visual redesign

### Shell

- **Sidebar**: instance logo + name (from `themeStore`) instead of the lock icon and
  "Admin Panel". Two labelled clusters (Operate / Settings), collapsible to an icon rail on
  tablets, a drawer on phones. Queue count pills stay.
- **Top bar**: breadcrumb (`Settings / Media & storage`), global search (`Ctrl+K`), sudo
  countdown chip, link back to the app.
- **Content width**: settings pages cap at about 760px (readable forms); tables and the
  dashboard go full width.

### Shared primitives (replace the 20 copies of page CSS)

`AdminPage` (title, description, actions slot) · `SettingsSection` (card with heading and
one-line why) · `SettingRow` (label + help on the start side, control on the end side,
"changed" dot, reset-to-default) · `SecretField` (write-only, shows "set / not set") ·
`SaveBar` (sticky, appears when dirty: Discard / Save, one save model for every page,
today each page invents its own) · `StatusPill` · `StatTile` (grow existing `StatsCard`) ·
`EmptyState` · `DataTable` everywhere (exists, under-used) with a card layout below 640px.

### Finding things (the memorability win)

- **Command palette** searches every registry entry by label, help text and raw key,
  plus every page. Typing "retention" or "pow" jumps straight to the row and highlights it.
- **"Changed settings" view**: one list of everything that differs from defaults. Doubles as
  documentation of how this instance is configured.
- Each settings page opens with a short summary line ("Sign-ups are invite-only, captcha on,
  email confirmation required") so the state is readable without scanning toggles.

### Dashboard

Top to bottom by urgency: **Needs attention** (reports, approvals, appeals, dead letters,
failing peers, as clickable tiles) → **Health** (services, queues, storage) → **Trends**
(sparklines for sign-ups, posts, active users, federation throughput) → **Recent staff
actions** (last 5 audit entries).

## 5. Dynamic colors: one design for app + admin

Good news: the admin already consumes the global tokens (`--color-primary`,
`--color-surface-*`, …) and the root layout applies the instance theme, so most of the
panel already follows the instance palette and dark mode. Remaining work:

1. **Remove hardcoded colors** (about 150 hex/rgba values): `AdminProfileActions` (42),
   `AdminPostActions` (21), user detail page (12), analytics (11), roles (10), users list (7).
   Status colors map to `--color-success/warning/danger/info` and their `-soft`/`-on-*-soft`
   pairs. The Theme page's 37 are mostly the color pickers' own defaults and can stay.
2. **Chart palette from the theme**: analytics/sparkline series derive from `--color-primary`
   plus the semantic tokens, so charts match the brand in light and dark.
3. **Admin-only derived tokens**, computed in `theme.ts` from the instance palette, not
   separately configured: `--admin-rail-bg`, `--admin-active` (primary at low alpha),
   `--admin-focus`. Admins set one theme; the panel derives its chrome.
4. **Theme editor preview gains an "Admin panel" tab** next to the app preview, so admins
   see both surfaces before saving.
5. Respect the viewer's light/dark choice in the panel (same `resolvedMode`), and check
   contrast of the derived tokens against WCAG AA in the editor (warn, don't block).

No new color settings are needed. This keeps the "no hardcoded branding" rule.

## 6. i18n

Since the panel has zero `$t` today, do the extraction as part of each migration PR rather
than a separate pass: registry `label_key`/`help_key` go into `en.json` under `admin.*`, and
every rebuilt page uses `$t`. RTL comes for free if primitives use logical properties.

## 7. Delivery plan (PR batches)

| # | PR | Size | Depends |
|---|---|---|---|
| 1 | `fix(admin): settings allowlist, secret masking, audit redaction` (registry skeleton with the currently-exposed keys + all secrets, typed casting, tests) | M | none, ship first |
| 2 | `feat(admin): admin UI primitives + shell` (AdminPage, SettingsSection, SettingRow, SaveBar, StatusPill, sidebar with instance branding, top bar) and hex-to-token cleanup | M | none |
| 3 | `feat(admin): registry schema endpoint + generic settings pages` (fill the registry with all ~200 keys, `/admin/settings/*` routes, redirects, nav rewrite in `admin-nav.ts`) | L | 1, 2 |
| 4 | `refactor(admin): move bespoke editors into new IA` (Registration split into settings + Invites, retention consolidation, report-email throttles merged, Blocklists page) | M | 3 |
| 5 | `feat(admin): command palette + changed-settings view + per-setting reset` | M | 3 |
| 6 | `feat(admin): dashboard redesign + DataTable everywhere + mobile card tables` | M | 2 |
| 7 | `feat(theme): admin preview tab, derived admin tokens, chart palette, contrast check` | S | 2 |

Gates for each: `mix precommit`, `npm run check` (0 errors), `node scripts/check-i18n.mjs`.

## 8. Decisions (2026-11-13)

- **Report-email throttles: keep both.** `report_email_throttle_seconds` (per-report
  emails, 60s) and `moderation_email_throttle_seconds` (staff digest, 600s) stay separate,
  shown side by side in Moderation & safety with labels that say which email each one
  governs.
- **Expert tunables go behind an "Advanced" disclosure** on each settings page. The
  registry carries an `advanced: true` flag per entry (e.g. `pow_difficulty`,
  `explore_trending_*` weights, prewarm intervals, key cache).
- **One permission per settings group.** Every registry entry carries a `group`; PR 3 maps
  each group to a permission, reusing existing ones (`federation.manage`,
  `email.manage`, `theme.manage`) and adding the missing ones. PR 1 keeps
  `settings.manage` so the security fix ships without a permission migration.

## 9. Progress

- PR 1 (`fix/admin-settings-registry`): `Config.Registry` with the keys the UI writes,
  the per-tier limits and every known secret; allowlisted, typed, all-or-nothing writes;
  secrets masked on read (registered or secret-looking name) and redacted in the audit log;
  stored strings typed on cache load. Also fixes: Tiers page saved limits as strings
  (`"800"`), which the post changeset used as a length; `false` settings were listed as
  `{"value": false}`.
- PR 2 (`feat/admin-shell-primitives`): instance-branded sidebar with Operate/Configure
  clusters, top bar (breadcrumb, sudo countdown, mobile drawer), AdminPage /
  SettingsSection / SettingRow / SaveBar / StatusPill, hardcoded colors moved to tokens.
- PR 3 (`feat/admin-settings-pages`): the registry covers every `Config.get` tunable
  (about 160 keys, each with default, unit, section, Advanced flag and conditional
  visibility); a test fails if a new key is neither registered nor deliberately unmanaged,
  and another if a rendered setting lacks an English label. One permission per group
  (`settings.<group>`, reusing `settings.manage`, `theme.manage`, `federation.manage`),
  granted on migrate to every role holding `settings.manage`. `GET /admin/settings/schema`
  and `DELETE /admin/settings/:key` (reset). Twelve `/admin/settings/<group>` pages rendered
  from the schema; dedicated editors become hidden nav items under their group;
  `/admin/instance/general` redirects. Still unmanaged and needing editors: `mrf_policies`,
  `mrf_keyword_replace`, `upload_filters`.
- PR 4 (`refactor/admin-move-editors`): Blocklists (content filters, IPs, email domains,
  media hashes, hashtags) split out of Moderation into `/admin/moderation/blocklists`, with
  old `?tab=` links redirected; Registration reduced to Invites (mode and bot protection live
  in Sign-up & access); Takedowns, Federation delivery and Email show read-only summaries
  linking to the settings pages instead of duplicate editors. Also fixes the rail lighting up
  "Reports & queue" on every `/admin/moderation/*` page.
- PR 5 (`feat/admin-command-palette`): Ctrl/Cmd+K search over every admin page (hidden editors
  included) and every registry setting by label, help text, raw key or group; picking a setting
  deep-links to `/admin/settings/<group>#setting-<key>`, which opens its Advanced section,
  scrolls to it, focuses it and flashes the row. New `/admin/settings/changed` lists every
  stored (non-default) setting with value, default, a link and reset. `Modal` now honours
  `data-autofocus` for its initial focus.
- PR 6 (`feat/admin-dashboard-tables`): dashboard reordered by urgency (needs-attention tiles for
  non-empty queues only, incl. failed deliveries and stopped peers; 14-day trends with zero-filled
  sparklines plus all-time totals; service health; last 6 staff actions), each section gated on its
  permission; the nav-card hub is gone (sidebar + Ctrl+K cover it). `DataTable` stacks rows into
  labelled cards below 640px and hides blank cells.


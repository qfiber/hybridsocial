# HybridSocial — Remaining Backend Work

Status: 884 tests passing, 147 source files, 64 test files
Date: 2026-03-22

---

## Priority 1: Required for Deployment

### 1. Instance Info & NodeInfo
- `GET /api/v1/instance` — name, description, stats (users, posts, connections), rules, version, languages, registrations status
- `GET /.well-known/nodeinfo` — NodeInfo 2.0 endpoint for federation discovery
- `GET /nodeinfo/2.0` — actual NodeInfo document (software name/version, usage stats, features)
- Wire instance stats from database (user count, post count, etc.)

### 2. Content Sanitization
- Replace basic HTML escaping with proper sanitizer
- Allowlist safe HTML tags: `<p>`, `<br>`, `<a>`, `<strong>`, `<em>`, `<code>`, `<pre>`, `<blockquote>`, `<ul>`, `<ol>`, `<li>`, `<span>`
- Strip: `<script>`, `<style>`, `<iframe>`, `<object>`, `<embed>`, event handlers (`onclick`, etc.)
- Sanitize `<a>` href (only http/https, add `rel="nofollow noopener"`, `target="_blank"`)
- Add `HtmlSanitizeEx` or build custom sanitizer
- Apply on post creation and when rendering federated content

### 3. Backup System
- `POST /api/v1/admin/backup` — trigger encrypted database backup
- `GET /api/v1/admin/backups` — list backups
- `GET /api/v1/admin/backups/:id/download` — download backup
- `POST /api/v1/admin/backups/:id/restore` — restore (requires encryption key)
- Implementation: `pg_dump` → gzip → AES-256-GCM encrypt
- Store passphrase hash only (never the passphrase itself)
- Background worker for backup generation
- `backup_jobs` table (already in spec)

### 4. Actor Migration
- Outgoing: user sets up new account elsewhere, sends AP `Move` activity
- Incoming: receive `Move`, verify `alsoKnownAs`, transfer followers
- `alsoKnownAs` field on identities (migration)
- API: `POST /api/v1/accounts/migrate` — initiate outgoing migration
- Old account enters redirect state (frozen, shows redirect)
- Support both incoming and outgoing

### 5. Password Reset Flow
- Wire `POST /api/v1/auth/password/reset` to send reset email via Swoosh
- `POST /api/v1/auth/password/change` — verify token, set new password
- Token expiry (1 hour)
- Rate limit on reset requests

### 6. Registration Flow Hardening
- Full registration pipeline: validate email domain against banned list, check handle reservation, send confirmation email
- PoW (Proof of Work) on registration endpoint: client must solve a partial hash collision before server accepts
  - `GET /api/v1/auth/pow_challenge` — returns challenge (random prefix + difficulty)
  - Client computes nonce where SHA256(prefix + nonce) has N leading zero bits
  - Submit nonce with registration request, server verifies
  - Difficulty configurable via admin settings (default: 16 bits)
- Cloudflare Turnstile integration (captcha alternative):
  - `POST /api/v1/auth/register` requires `cf_turnstile_token` field
  - Backend verifies token with Cloudflare's siteverify API
  - Site key + secret key configurable via instance settings
  - Optional: admin can disable captcha requirement
  - Also apply to password reset endpoint

---

## Priority 2: Important Features

### 6. Video Streams (Reels)
- `stream_views` table (post_id, identity_id, watch_duration, total_duration, completed, replayed, source)
- Enforce 9:16 aspect ratio for video_stream post type
- Max duration configurable (default 90s)
- Discovery algorithm: watch completion rate, replay rate, engagement, freshness
- `GET /api/v1/timelines/streams` — video streams feed
- View tracking endpoint: `POST /api/v1/statuses/:id/view`

### 7. Algorithmic Feed ("For You")
- `user_interaction_signals` table (identity_id, target_identity_id, interaction_count, last_interaction, content_tags)
- Update signals on reactions, replies, boosts, profile views
- Ranking: interaction affinity (40%), engagement velocity (20%), content affinity (15%), social proximity (10%), freshness (10%), diversity injection (5%)
- `GET /api/v1/timelines/home?algorithm=true` — switch between chronological and algorithmic
- Background worker to precompute signals

### 8. Relay Support
- AP relay subscription for small instance discovery
- `POST /api/v1/admin/relays` — subscribe to relay
- `DELETE /api/v1/admin/relays/:id` — unsubscribe
- `GET /api/v1/admin/relays` — list relays
- Handle incoming `Announce` from relays
- `relays` table already exists

### 9. NATS Integration
- Replace Phoenix.PubSub with NATS JetStream for event pipeline
- Event types: post.created, post.deleted, post.updated, reaction.created, follow.created, etc.
- Workers subscribe to NATS streams instead of PubSub
- Federation delivery via NATS queue (replace current Task.Supervisor approach)
- Keep PubSub for real-time SSE/WebSocket (NATS for durable, PubSub for ephemeral)

---

## Priority 3: Polish & Nice-to-haves

### 10. Announcement Banners
- `instance_announcements` table (id, content, starts_at, ends_at, all_day, published, timestamps)
- `GET /api/v1/announcements` — active announcements
- `POST /api/v1/admin/announcements` — create
- `DELETE /api/v1/admin/announcements/:id` — remove
- `POST /api/v1/announcements/:id/dismiss` — user dismisses

### 11. IP & Email Domain Blocks
- `POST /api/v1/admin/ip_blocks` — block IP or CIDR range
- Check on registration and login
- `email_domain_blocks` — block registrations from disposable email providers
- Wire into registration flow: check `banned_domains` table with type `email`

### 12. Donation Page API
- `GET /api/v1/instance/funding` — returns enabled funding methods
- `POST /api/v1/donations` — record a donation
- Admin endpoints for managing funding methods
- Wire existing `instance_funding` and `donations` tables

### 13. Post Analytics (Premium)
- Track: views, reach (unique viewers), engagement rate
- `post_analytics` table or use existing counters + new view tracking
- `GET /api/v1/statuses/:id/analytics` — premium-only endpoint
- Dashboard data for premium users

### 14. Login Notification Emails
- Wire `Hybridsocial.Emails.login_notification_email/3` into the login flow
- Track IP and user agent on login
- Send email on new device/IP detection
- `login_history` table for tracking

### 15. Notification Digest Emails
- Background worker that sends notification digests
- Configurable frequency: immediate, hourly, daily, never
- Uses `Hybridsocial.Emails.notification_digest_email/2`
- Respects notification preferences

---

## Estimated Effort

| Priority | Items | Rough Scope |
|----------|-------|-------------|
| P1 (1-6) | Deployment blockers | ~5 hours |
| P2 (7-10) | Important features | ~6 hours |
| P3 (11-16) | Polish | ~4 hours |
| **Total** | **16 items** | **~15 hours** |

## After Backend

- Frontend (SvelteKit) — Phase 9
- Mobile (Flutter) — Phase 10

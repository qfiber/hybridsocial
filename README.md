# HybridSocial

A decentralized social networking platform built on [ActivityPub](https://www.w3.org/TR/activitypub/), designed for communities, organizations, and individuals who want control over their social experience.

## Features

### Social
- **Posts** with markdown, media attachments, polls, and content warnings
- **7 reaction types** (Like, Love, Care, Angry, Sad, LOL, WTF)
- **Boosts & Quote Posts** for sharing content
- **Threaded conversations** with reply chains
- **Direct Messages** with 1:1 and group DMs
- **Groups** — public, private, and local-only with screening and auto-approval
- **Pages/Organizations** with business profiles and branding
- **Lists** for curated feeds
- **Bookmarks**, pinned posts, scheduled posts

### Federation
- Full **ActivityPub** support — interoperable with Mastodon, Pleroma, Akkoma, Misskey, and others
- **WebFinger** discovery with UUID-based actor URLs (handle changes don't break federation)
- **HTTP Signature** verification for secure server-to-server communication
- **Actor migration** (Move activity) for transferring accounts between instances
- **Relay support** for small instance discovery
- **Instance policies** — allow, silence, suspend, block media, force NSFW per domain

### Discovery
- **Full-text search** (PostgreSQL + OpenSearch dual backend)
- **Trending** posts and hashtags with manipulation resistance
- **Algorithmic feed** ("For You") alongside chronological
- **Video Streams** — reels-like vertical video feed
- **Hashtag** timelines and exploration

### Security
- **RBAC** — Role-Based Access Control with 24 granular permissions and 4 system roles
- **2FA** — TOTP with QR code setup and recovery codes
- **OAuth2 + PKCE** for third-party app authentication
- **PoW challenges** and **Cloudflare Turnstile** for registration protection
- **Rate limiting** — per-endpoint with configurable limits via admin panel
- **Content sanitization** — HTML allowlisting, SSRF prevention, magic byte validation
- **Audit logging** — immutable log of all security events
- **HTTP security headers** — CSP, HSTS, X-Frame-Options, Referrer-Policy
- **Encrypted backups** — AES-256-GCM with admin-provided passphrase
- **Session invalidation** on password change
- **OWASP Top 10** compliant

### Admin
- **Dashboard** with instance stats
- **User management** — suspend, warn, delete
- **Moderation** — reports, content filters, banned domains, IP blocks, webhooks
- **Federation dashboard** — known instances, policies, delivery queue
- **Theme editor** — live preview with WCAG contrast checking
- **Role management** — create custom roles with specific permissions
- **Configurable everything** — all settings editable at runtime via database, no restart needed
- **Backup system** — encrypted database backups

### Premium & Monetization
- **Verification badges** — manual, domain, or paid verification
- **Premium features** — extended post length, markdown, HD video, post analytics
- **Donations** — Stripe, PayPal, Bitcoin, Ethereum support
- **Data portability** — full export/import, GDPR-compliant account deletion

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Backend | Elixir / Phoenix |
| Frontend | SvelteKit (Svelte 5) |
| Database | PostgreSQL |
| Cache | Valkey (Redis-compatible) |
| Search | OpenSearch |
| Message Broker | NATS JetStream |
| Media Processing | libvips (images), ffmpeg (video) |
| WAF | Caddy + Coraza |
| Email | Swoosh (SMTP + Resend) |
| Mobile (planned) | Flutter |

## Quick Start

### Prerequisites
- Elixir 1.18+ / Erlang/OTP 28+
- Node.js 22+
- Docker & Docker Compose
- PostgreSQL 17 (via Docker)

### 1. Clone and setup

```bash
git clone git@github.com:qfiber/hybridsocial.git
cd hybridsocial
```

### 2. Start services

```bash
docker compose up -d
```

This starts PostgreSQL, Valkey, NATS, and OpenSearch.

### 3. Setup backend

```bash
cd backend
mix deps.get
mix ecto.setup      # Creates DB, runs migrations, seeds default settings
mix phx.server      # Starts at http://localhost:4000
```

### 4. Setup frontend

```bash
cd frontend
npm install
VITE_API_URL=http://localhost:4000 npm run dev  # Starts at http://localhost:5173
```

### 5. Create first admin

```bash
# Register via the UI at http://localhost:5173/register
# Then make yourself admin:
cd backend
mix run -e '
  alias Hybridsocial.{Repo, Accounts.Identity, Auth.RBAC}
  import Ecto.Query
  identity = Identity |> where(handle: "your_handle") |> Repo.one!()
  RBAC.assign_role(identity.id, "owner", identity.id)
  IO.puts("Done - you are now owner")
'
```

## Project Structure

```
hybridsocial/
├── backend/              # Elixir/Phoenix API (164 source files, 1000+ tests)
│   ├── lib/
│   │   ├── hybridsocial/           # Business logic contexts
│   │   │   ├── accounts/           # Identity, users, organizations
│   │   │   ├── auth/               # JWT, OAuth2, RBAC, 2FA, PoW
│   │   │   ├── social/             # Posts, reactions, follows, groups
│   │   │   ├── messaging/          # DMs, conversations
│   │   │   ├── federation/         # ActivityPub, WebFinger, HTTP signatures
│   │   │   ├── feeds/              # Timelines, algorithmic ranking
│   │   │   ├── search/             # OpenSearch, PostgreSQL full-text
│   │   │   ├── media/              # Upload, validation, S3 storage
│   │   │   ├── moderation/         # Reports, audit log, content filters
│   │   │   ├── notifications/      # In-app, push, email digests
│   │   │   ├── content/            # Sanitizer, link previews, custom emoji
│   │   │   ├── premium/            # Verification, subscriptions
│   │   │   └── admin/              # Backups, announcements
│   │   └── hybridsocial_web/       # API controllers, plugs, router
│   ├── priv/repo/migrations/       # 25 database migrations
│   └── test/                       # 1000+ tests
├── frontend/             # SvelteKit web app (120 files, 43 pages)
│   └── src/
│       ├── lib/
│       │   ├── api/                # Typed API client
│       │   ├── components/         # 41 reusable components
│       │   ├── stores/             # Auth, theme, notifications
│       │   └── utils/              # i18n, RTL, time formatting
│       ├── routes/                 # 43 pages
│       └── locales/                # i18n translation files
├── docs/                 # Specifications
│   └── SPEC.md           # Full implementation specification
├── docker-compose.yml    # Development services
└── .github/workflows/    # CI/CD pipeline
```

## API

The backend exposes 100+ REST API endpoints. Key groups:

| Group | Endpoints |
|-------|-----------|
| Auth | `/api/v1/auth/*` — register, login, 2FA, password reset |
| Accounts | `/api/v1/accounts/*` — profiles, follow, block, mute |
| Statuses | `/api/v1/statuses/*` — posts, reactions, boosts |
| Timelines | `/api/v1/timelines/*` — home, public, hashtag, list, group |
| Conversations | `/api/v1/conversations/*` — DMs |
| Groups | `/api/v1/groups/*` — communities |
| Notifications | `/api/v1/notifications/*` |
| Search | `/api/v1/search` |
| Admin | `/api/v1/admin/*` — moderation, settings, federation |
| Federation | `/.well-known/webfinger`, `/actors/*`, `/inbox` |

## Testing

```bash
cd backend
mix test              # Run all 1000+ tests
mix test --only unit  # Unit tests only
mix test --cover      # With coverage report
```

## Deployment

### Single Server (Docker Compose)

```bash
docker compose -f docker-compose.prod.yml up -d
```

### Cluster

HybridSocial scales horizontally via BEAM clustering:
1. Migrate media to S3
2. Add app server nodes with shared `RELEASE_COOKIE`
3. `libcluster` handles automatic node discovery
4. Phoenix PubSub distributes WebSocket/SSE connections across nodes

See [docs/SPEC.md](docs/SPEC.md) for the full clustering guide.

## Configuration

All settings are database-backed and editable at runtime via the admin panel. Environment variables are only used for infrastructure:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Phoenix secret (generate with `mix phx.gen.secret`) |
| `VALKEY_URL` | Valkey/Redis connection |
| `NATS_URL` | NATS JetStream connection |
| `OPENSEARCH_URL` | OpenSearch connection |
| `S3_*` | S3-compatible storage credentials |
| `SMTP_*` or `RESEND_API_KEY` | Email provider |
| `PHX_HOST` | Production hostname |
| `FRONTEND_URL` | Frontend origin for CORS |

## Contributing

HybridSocial is open source under the AGPL v3 license. Contributions are welcome.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`mix test`)
4. Commit your changes
5. Push to the branch
6. Open a Pull Request

## License

[GNU Affero General Public License v3.0](LICENSE) — you can use, modify, and distribute this software, but any modifications must be published under the same license, even when running as a network service.

## Acknowledgments

Built with Elixir, Phoenix, SvelteKit, and the ActivityPub protocol.

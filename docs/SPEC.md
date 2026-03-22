# HybridSocial — Implementation Specification

Version: 1.0
License: AGPL v3
Date: 2026-03-21

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture](#2-architecture)
3. [Tech Stack](#3-tech-stack)
4. [Data Model](#4-data-model)
5. [API Surface](#5-api-surface)
6. [Authentication & Authorization](#6-authentication--authorization)
7. [ActivityPub Federation](#7-activitypub-federation)
8. [Media Pipeline](#8-media-pipeline)
9. [Direct Messaging](#9-direct-messaging)
10. [Groups & Communities](#10-groups--communities)
11. [Feeds & Ranking](#11-feeds--ranking)
12. [Video Streams](#12-video-streams)
13. [Search & Trending](#13-search--trending)
14. [Notifications](#14-notifications)
15. [Reactions & Custom Emoji](#15-reactions--custom-emoji)
16. [Moderation & Safety](#16-moderation--safety)
17. [Pages & Organizations](#17-pages--organizations)
18. [Verification & Premium](#18-verification--premium)
19. [Monetization & Donations](#19-monetization--donations)
20. [Admin Panel](#20-admin-panel)
21. [Configuration System](#21-configuration-system)
22. [Email System](#22-email-system)
23. [Security](#23-security)
24. [Data Portability](#24-data-portability)
25. [Internationalization](#25-internationalization)
26. [Accessibility](#26-accessibility)
27. [Testing Strategy](#27-testing-strategy)
28. [CI/CD Pipeline](#28-cicd-pipeline)
29. [Deployment](#29-deployment)
30. [Scaling & Clustering](#30-scaling--clustering)
31. [Backup & Recovery](#31-backup--recovery)
32. [Build Order](#32-build-order)

---

## 1. System Overview

HybridSocial is a decentralized social networking platform that uses ActivityPub strictly as a federation protocol while maintaining full control over permissions, groups, pages, feeds, ranking, and moderation internally.

### Core Principles

- **Backend is authoritative**: All permissions, visibility, and relationships enforced server-side
- **Frontend is a pure API client**: RTL detection, animations, font selection are frontend concerns
- **ActivityPub is transport**: Used for federation only, not as the internal data model
- **Internal model ≠ external representation**: Internal schema optimized for features, AP objects are projections
- **No hardcoded limits**: All settings configurable at runtime via database-backed admin panel
- **Privacy and accessibility from day one**: WCAG 2.1 AA, GDPR compliance, data portability
- **Open source**: AGPL v3 — modifications must be published, even for SaaS deployments

---

## 2. Architecture

### Services

```
┌─────────────────────────────────────────────────────┐
│                   Caddy + Coraza (WAF)              │
│              TLS termination, rate limiting          │
└──────────────────────┬──────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          │            │            │
          ▼            ▼            ▼
   ┌──────────┐ ┌──────────┐ ┌──────────┐
   │ Phoenix  │ │ Phoenix  │ │ Phoenix  │
   │ API Node │ │ API Node │ │ API Node │
   │  (BEAM)  │ │  (BEAM)  │ │  (BEAM)  │
   └────┬─────┘ └────┬─────┘ └────┬─────┘
        │             │            │
        └─────────────┼────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
   ┌────▼────┐  ┌─────▼─────┐  ┌───▼───┐
   │PostgreSQL│  │   Valkey  │  │ NATS  │
   │         │  │  (cache)  │  │(broker)│
   └─────────┘  └───────────┘  └───┬───┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
              ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼──────┐
              │ Federation │  │   Feed    │  │   Media    │
              │   Worker   │  │  Worker   │  │ Processor  │
              └────────────┘  └───────────┘  └────────────┘
                                                    │
                                              ┌─────▼─────┐
                                              │  S3/Local  │
                                              │  Storage   │
                                              └───────────┘
                    ┌───────────┐
                    │ OpenSearch │
                    │  (search) │
                    └───────────┘
```

### Data Flow

- **Post creation**: Client → API → PostgreSQL → NATS event → [Feed Worker, Search Indexer, Federation Worker, Notification Service]
- **Federation inbound**: Remote Server → Caddy → API /inbox → Signature Verify → NATS → Federation Worker → PostgreSQL
- **Feed serving**: API → Valkey (cached feed) → Client. Cache miss → PostgreSQL → compute → Valkey → Client
- **Search**: API → OpenSearch → Client
- **Real-time**: API → SSE (feeds, notifications) or WebSocket (DMs) → Client

---

## 3. Tech Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Backend | Elixir / Phoenix | BEAM VM: preemptive concurrency, fault tolerance, built-in clustering, hot reload |
| Frontend Web | SvelteKit | Tiny runtime, no virtual DOM, built-in animations, fast feed rendering |
| Mobile | Flutter | Single codebase iOS + Android, good WebSocket support |
| Database | PostgreSQL | Proven, feature-rich, excellent Elixir support via Ecto |
| Cache | Valkey | Redis-compatible, BSD licensed, high performance |
| Search | OpenSearch | Full-text + fuzzy search, trending aggregations, Apache 2.0 |
| Message Broker | NATS JetStream | Simple, fast, persistent, Go-native, easy to operate |
| Media (images) | libvips | 4-8x faster than ImageMagick, constant memory, safer |
| Media (video) | ffmpeg | Industry standard transcoding |
| Virus Scan | ClamAV (clamd) | Open source, daemon mode for performance |
| WAF | Coraza + Caddy | ModSecurity successor, Go, actively maintained, auto TLS |
| Email | Swoosh | Elixir-native, adapters for SMTP + Resend |
| E2EE (future) | Olm/Megolm | Apache 2.0, proven in Matrix, good for group DMs |
| Push Notifications | FCM (Android) + APNs (iOS) | Platform standard |
| Translations | Weblate | Open source, self-hostable, community contribution workflow |
| CI/CD | GitHub Actions | Standard, free for open source |
| Deployment | Docker Compose | Single server MVP, cluster-ready |
| License | AGPL v3 | Copyleft for network use, compatible with Apache 2.0/MIT deps |

---

## 4. Data Model

### 4.1 Identity & Actors

```sql
-- Shared identity table (primary key for all actor types)
identities
  id              UUID PRIMARY KEY
  type            ENUM (user, organization)
  handle          VARCHAR UNIQUE        -- @username (changeable)
  ap_actor_url    VARCHAR UNIQUE        -- https://domain/actors/{uuid} (permanent)
  public_key      TEXT
  private_key     TEXT (encrypted at rest)
  inbox_url       VARCHAR
  outbox_url      VARCHAR
  followers_url   VARCHAR
  avatar_id       UUID REFERENCES media
  header_id       UUID REFERENCES media
  display_name    VARCHAR
  bio             TEXT
  metadata        JSONB                 -- custom profile fields
  is_locked       BOOLEAN DEFAULT false -- requires follow approval
  is_bot          BOOLEAN DEFAULT false
  is_suspended    BOOLEAN DEFAULT false
  suspended_at    TIMESTAMP
  created_at      TIMESTAMP
  updated_at      TIMESTAMP
  deleted_at      TIMESTAMP             -- soft delete

-- Handle history for preventing impersonation
handle_history
  id              UUID PRIMARY KEY
  identity_id     UUID REFERENCES identities
  old_handle      VARCHAR
  changed_at      TIMESTAMP
  reserved_until  TIMESTAMP             -- 12 months after change

-- User-specific details
users
  identity_id     UUID PRIMARY KEY REFERENCES identities
  email           VARCHAR UNIQUE (encrypted at rest)
  password_hash   VARCHAR
  locale          VARCHAR DEFAULT 'en'
  timezone        VARCHAR
  last_login_at   TIMESTAMP
  confirmed_at    TIMESTAMP
  confirmation_token VARCHAR
  reset_token     VARCHAR
  reset_token_at  TIMESTAMP
  otp_secret      VARCHAR (encrypted)   -- 2FA
  otp_enabled     BOOLEAN DEFAULT false

-- Organization/Page-specific details
organizations
  identity_id     UUID PRIMARY KEY REFERENCES identities
  owner_id        UUID REFERENCES identities
  website         VARCHAR
  category        VARCHAR

-- Organization roles
organization_roles
  id              UUID PRIMARY KEY
  organization_id UUID REFERENCES organizations
  identity_id     UUID REFERENCES identities
  role            ENUM (admin, editor, moderator)
  granted_by      UUID REFERENCES identities
  created_at      TIMESTAMP
```

### 4.2 Social Graph

```sql
follows
  id              UUID PRIMARY KEY
  follower_id     UUID REFERENCES identities
  followee_id     UUID REFERENCES identities
  status          ENUM (pending, accepted, rejected)
  notify          BOOLEAN DEFAULT true
  created_at      TIMESTAMP
  updated_at      TIMESTAMP
  UNIQUE (follower_id, followee_id)

blocks
  id              UUID PRIMARY KEY
  blocker_id      UUID REFERENCES identities
  blocked_id      UUID REFERENCES identities
  created_at      TIMESTAMP
  UNIQUE (blocker_id, blocked_id)

mutes
  id              UUID PRIMARY KEY
  muter_id        UUID REFERENCES identities
  muted_id        UUID REFERENCES identities
  mute_notifications BOOLEAN DEFAULT true
  expires_at      TIMESTAMP             -- optional timed mute
  created_at      TIMESTAMP
  UNIQUE (muter_id, muted_id)
```

### 4.3 Posts

```sql
posts
  id              UUID PRIMARY KEY
  identity_id     UUID REFERENCES identities   -- author
  post_type       ENUM (text, media, video_stream, poll, article)
  content         TEXT                          -- markdown source
  content_html    TEXT                          -- rendered HTML (for AP)
  visibility      ENUM (public, followers, group, direct, list)
  sensitive       BOOLEAN DEFAULT false
  spoiler_text    VARCHAR                       -- content warning
  language        VARCHAR(5)                    -- BCP 47 tag
  group_id        UUID REFERENCES groups
  page_id         UUID REFERENCES organizations
  list_id         UUID REFERENCES lists         -- for visibility: list
  parent_id       UUID REFERENCES posts         -- immediate parent (reply)
  root_id         UUID REFERENCES posts         -- conversation root
  quote_id        UUID REFERENCES posts         -- quoted post (quote post)
  reply_count     INTEGER DEFAULT 0
  boost_count     INTEGER DEFAULT 0
  reaction_count  INTEGER DEFAULT 0
  is_pinned       BOOLEAN DEFAULT false
  edited_at       TIMESTAMP
  edit_expires_at TIMESTAMP                     -- 24h after creation
  scheduled_at    TIMESTAMP                     -- for scheduled posts
  published_at    TIMESTAMP                     -- actual publish time
  created_at      TIMESTAMP
  updated_at      TIMESTAMP
  deleted_at      TIMESTAMP                     -- soft delete

-- Post revision history
post_revisions
  id              UUID PRIMARY KEY
  post_id         UUID REFERENCES posts
  content         TEXT                          -- markdown at this revision
  content_html    TEXT
  edited_at       TIMESTAMP
  revision_number INTEGER

-- Direct message recipients / list recipients
post_recipients
  post_id         UUID REFERENCES posts
  identity_id     UUID REFERENCES identities
  UNIQUE (post_id, identity_id)

-- Post-media associations
post_media
  post_id         UUID REFERENCES posts
  media_id        UUID REFERENCES media
  position        INTEGER                       -- ordering
  UNIQUE (post_id, media_id)
```

### 4.4 Media

```sql
media
  id              UUID PRIMARY KEY
  identity_id     UUID REFERENCES identities    -- uploader
  content_type    VARCHAR                       -- verified MIME type
  file_size       BIGINT
  storage_backend ENUM (local, s3)
  storage_path    VARCHAR                       -- UUID-based path
  blurhash        VARCHAR
  alt_text        TEXT
  width           INTEGER
  height          INTEGER
  duration        FLOAT                         -- video/audio seconds
  thumbnail_path  VARCHAR
  processing_status ENUM (pending, processing, ready, failed)
  metadata        JSONB                         -- dimensions, codec, etc (NO original filename, NO EXIF)
  created_at      TIMESTAMP
  deleted_at      TIMESTAMP

-- Video transcoded variants
media_variants
  id              UUID PRIMARY KEY
  media_id        UUID REFERENCES media
  resolution      VARCHAR                       -- "720p", "480p", "240p"
  storage_path    VARCHAR
  file_size       BIGINT
  content_type    VARCHAR
  created_at      TIMESTAMP
```

### 4.5 Groups

```sql
groups
  id              UUID PRIMARY KEY
  name            VARCHAR
  description     TEXT
  visibility      ENUM (public, private, local_only)
  join_policy     ENUM (open, screening, approval, invite_only)
  ap_actor_url    VARCHAR                       -- for federated groups
  public_key      TEXT
  private_key     TEXT (encrypted)
  avatar_id       UUID REFERENCES media
  header_id       UUID REFERENCES media
  member_count    INTEGER DEFAULT 0
  post_count      INTEGER DEFAULT 0
  created_by      UUID REFERENCES identities
  created_at      TIMESTAMP
  updated_at      TIMESTAMP
  deleted_at      TIMESTAMP

group_screening_config
  group_id        UUID PRIMARY KEY REFERENCES groups
  require_profile_image BOOLEAN DEFAULT false
  min_account_age_days  INTEGER DEFAULT 0
  questions       JSONB                         -- array of question strings
  auto_approve_rules    JSONB                   -- conditions for auto-approval

group_members
  id              UUID PRIMARY KEY
  group_id        UUID REFERENCES groups
  identity_id     UUID REFERENCES identities
  role            ENUM (member, moderator, admin, owner)
  status          ENUM (pending, approved, rejected, banned)
  created_at      TIMESTAMP
  updated_at      TIMESTAMP
  UNIQUE (group_id, identity_id)

group_applications
  id              UUID PRIMARY KEY
  group_id        UUID REFERENCES groups
  identity_id     UUID REFERENCES identities
  answers         JSONB
  status          ENUM (pending, approved, rejected, auto_approved)
  reviewed_by     UUID REFERENCES identities
  created_at      TIMESTAMP
  reviewed_at     TIMESTAMP

group_invites
  id              UUID PRIMARY KEY
  group_id        UUID REFERENCES groups
  invited_by      UUID REFERENCES identities
  invited_id      UUID REFERENCES identities
  status          ENUM (pending, accepted, declined)
  created_at      TIMESTAMP
  responded_at    TIMESTAMP
```

### 4.6 Reactions

```sql
reactions
  id              UUID PRIMARY KEY
  post_id         UUID REFERENCES posts
  identity_id     UUID REFERENCES identities
  type            ENUM (like, love, care, angry, sad, lol, wtf)
  created_at      TIMESTAMP
  UNIQUE (post_id, identity_id)  -- one reaction per user per post
```

### 4.7 Boosts

```sql
boosts
  id              UUID PRIMARY KEY
  post_id         UUID REFERENCES posts         -- original post
  identity_id     UUID REFERENCES identities     -- booster
  created_at      TIMESTAMP
  deleted_at      TIMESTAMP
  UNIQUE (post_id, identity_id)
```

### 4.8 Polls

```sql
polls
  id              UUID PRIMARY KEY
  post_id         UUID REFERENCES posts
  multiple_choice BOOLEAN DEFAULT false
  expires_at      TIMESTAMP
  voters_count    INTEGER DEFAULT 0
  created_at      TIMESTAMP

poll_options
  id              UUID PRIMARY KEY
  poll_id         UUID REFERENCES polls
  text            VARCHAR
  position        INTEGER
  votes_count     INTEGER DEFAULT 0

poll_votes
  id              UUID PRIMARY KEY
  poll_id         UUID REFERENCES polls
  option_id       UUID REFERENCES poll_options
  identity_id     UUID REFERENCES identities
  created_at      TIMESTAMP
  UNIQUE (poll_id, identity_id, option_id)
```

### 4.9 Direct Messaging

```sql
conversations
  id              UUID PRIMARY KEY
  type            ENUM (direct, group_dm)
  created_at      TIMESTAMP
  updated_at      TIMESTAMP                     -- last message timestamp

conversation_participants
  conversation_id UUID REFERENCES conversations
  identity_id     UUID REFERENCES identities
  joined_at       TIMESTAMP
  last_read_message_id UUID REFERENCES messages
  notifications_enabled BOOLEAN DEFAULT true
  left_at         TIMESTAMP                     -- for group DMs
  UNIQUE (conversation_id, identity_id)

messages
  id              UUID PRIMARY KEY
  conversation_id UUID REFERENCES conversations
  sender_id       UUID REFERENCES identities
  content         TEXT                          -- plaintext (encrypted blob after E2EE)
  content_type    ENUM (text, image, video, file)
  media_id        UUID REFERENCES media
  reply_to_id     UUID REFERENCES messages
  edited_at       TIMESTAMP
  created_at      TIMESTAMP
  deleted_at      TIMESTAMP

message_delivery_status
  message_id      UUID REFERENCES messages
  recipient_id    UUID REFERENCES identities
  status          ENUM (sent, delivered, read)
  updated_at      TIMESTAMP
  UNIQUE (message_id, recipient_id)

-- DM privacy preferences
dm_preferences
  identity_id     UUID PRIMARY KEY REFERENCES identities
  allow_dms_from  ENUM (everyone, followers, mutual_followers, lists, nobody) DEFAULT everyone
  allow_group_dms BOOLEAN DEFAULT false
  allowed_lists   UUID[]                        -- list IDs when allow_dms_from = lists
```

### 4.10 Lists

```sql
lists
  id              UUID PRIMARY KEY
  identity_id     UUID REFERENCES identities    -- owner
  name            VARCHAR
  created_at      TIMESTAMP
  updated_at      TIMESTAMP

list_members
  list_id         UUID REFERENCES lists
  target_identity_id UUID REFERENCES identities
  added_at        TIMESTAMP
  UNIQUE (list_id, target_identity_id)
```

### 4.11 Bookmarks

```sql
bookmarks
  id              UUID PRIMARY KEY
  identity_id     UUID REFERENCES identities
  post_id         UUID REFERENCES posts
  created_at      TIMESTAMP
  UNIQUE (identity_id, post_id)
```

### 4.12 Notifications

```sql
notifications
  id              UUID PRIMARY KEY
  recipient_id    UUID REFERENCES identities
  actor_id        UUID REFERENCES identities    -- who caused it
  type            ENUM (follow, follow_request, reaction, boost, quote, reply, mention, poll_ended, group_invite, group_application, report, admin)
  target_type     VARCHAR                       -- "post", "group", "conversation"
  target_id       UUID
  read            BOOLEAN DEFAULT false
  created_at      TIMESTAMP

notification_preferences
  identity_id     UUID REFERENCES identities
  type            VARCHAR                       -- notification type
  email           BOOLEAN DEFAULT false
  push            BOOLEAN DEFAULT true
  in_app          BOOLEAN DEFAULT true
  UNIQUE (identity_id, type)
```

### 4.13 Verification & Premium

```sql
verifications
  id              UUID PRIMARY KEY
  identity_id     UUID REFERENCES identities
  type            ENUM (manual, domain, paid)
  status          ENUM (pending, approved, rejected, expired)
  verified_at     TIMESTAMP
  expires_at      TIMESTAMP
  metadata        JSONB
  created_at      TIMESTAMP
  updated_at      TIMESTAMP

subscriptions
  id              UUID PRIMARY KEY
  identity_id     UUID REFERENCES identities
  plan            ENUM (free, premium)
  status          ENUM (active, cancelled, expired, past_due)
  payment_provider ENUM (stripe, paypal, crypto)
  external_id     VARCHAR                       -- payment provider reference
  started_at      TIMESTAMP
  expires_at      TIMESTAMP
  cancelled_at    TIMESTAMP
  created_at      TIMESTAMP
```

### 4.14 Moderation

```sql
reports
  id              UUID PRIMARY KEY
  reporter_id     UUID REFERENCES identities
  reported_id     UUID REFERENCES identities    -- reported user
  target_type     VARCHAR                       -- "post", "conversation", "group"
  target_id       UUID
  category        ENUM (spam, harassment, hate_speech, illegal, misinformation, other)
  description     TEXT
  status          ENUM (pending, investigating, resolved, dismissed)
  assigned_to     UUID REFERENCES identities    -- moderator
  action_taken    VARCHAR
  federated       BOOLEAN DEFAULT false         -- sent as AP Flag
  created_at      TIMESTAMP
  resolved_at     TIMESTAMP

-- Immutable audit log
audit_log
  id              BIGSERIAL PRIMARY KEY         -- sequential, immutable
  actor_id        UUID REFERENCES identities    -- who performed the action
  action          VARCHAR                       -- "user.suspend", "post.delete", "report.resolve"
  target_type     VARCHAR
  target_id       UUID
  details         JSONB                         -- full context: reason, before/after state
  ip_address      INET
  created_at      TIMESTAMP
  -- NO updated_at, NO deleted_at — immutable

content_filters
  id              UUID PRIMARY KEY
  type            ENUM (word, phrase, regex)
  pattern         VARCHAR
  action          ENUM (flag, reject, replace)
  replacement     VARCHAR                       -- for replace action
  context         ENUM (posts, usernames, bios, all)
  created_by      UUID REFERENCES identities
  created_at      TIMESTAMP
  updated_at      TIMESTAMP

banned_domains
  domain          VARCHAR PRIMARY KEY
  type            ENUM (email, federation, both)
  reason          TEXT
  created_by      UUID REFERENCES identities
  created_at      TIMESTAMP
```

### 4.15 Federation

```sql
-- Remote actor cache
remote_actors
  id              UUID PRIMARY KEY
  ap_id           VARCHAR UNIQUE                -- full AP URL
  handle          VARCHAR
  domain          VARCHAR
  display_name    VARCHAR
  avatar_url      VARCHAR
  public_key      TEXT
  inbox_url       VARCHAR
  outbox_url      VARCHAR
  followers_url   VARCHAR
  last_fetched_at TIMESTAMP
  created_at      TIMESTAMP
  updated_at      TIMESTAMP

-- Instance-level federation policies
instance_policies
  domain          VARCHAR PRIMARY KEY
  policy          ENUM (allow, silence, suspend, block_media, force_nsfw)
  reason          TEXT
  created_by      UUID REFERENCES identities
  created_at      TIMESTAMP
  updated_at      TIMESTAMP

-- Federation delivery tracking
federation_deliveries
  id              UUID PRIMARY KEY
  activity_id     VARCHAR                       -- human-readable AP activity ID
  actor_id        UUID
  target_inbox    VARCHAR
  status          ENUM (pending, delivered, failed, retrying)
  attempts        INTEGER DEFAULT 0
  last_attempt_at TIMESTAMP
  error           TEXT
  created_at      TIMESTAMP

-- Deduplication
federation_dedup
  activity_hash   VARCHAR PRIMARY KEY           -- hash of actor + action + target
  activity_id     VARCHAR
  processed_at    TIMESTAMP
  expires_at      TIMESTAMP                     -- TTL for cleanup

-- Relays
relays
  id              UUID PRIMARY KEY
  inbox_url       VARCHAR UNIQUE
  status          ENUM (pending, accepted, rejected)
  created_at      TIMESTAMP
```

### 4.16 Custom Emoji

```sql
custom_emojis
  id              UUID PRIMARY KEY
  shortcode       VARCHAR UNIQUE                -- e.g., "blobcat"
  image_id        UUID REFERENCES media
  category        VARCHAR
  enabled         BOOLEAN DEFAULT true
  created_at      TIMESTAMP
  updated_at      TIMESTAMP
```

### 4.17 OAuth2

```sql
oauth_applications
  id              UUID PRIMARY KEY
  name            VARCHAR
  client_id       VARCHAR UNIQUE
  client_secret_hash VARCHAR
  redirect_uris   TEXT[]
  scopes          TEXT[]
  website         VARCHAR
  created_by      UUID REFERENCES identities
  created_at      TIMESTAMP

oauth_tokens
  id              UUID PRIMARY KEY
  identity_id     UUID REFERENCES identities
  application_id  UUID REFERENCES oauth_applications
  token_hash      VARCHAR UNIQUE
  refresh_token_hash VARCHAR UNIQUE
  scopes          TEXT[]
  expires_at      TIMESTAMP
  revoked_at      TIMESTAMP
  created_at      TIMESTAMP

oauth_authorization_codes
  code_hash       VARCHAR PRIMARY KEY
  application_id  UUID REFERENCES oauth_applications
  identity_id     UUID REFERENCES identities
  redirect_uri    VARCHAR
  scopes          TEXT[]
  code_challenge  VARCHAR                       -- PKCE
  code_challenge_method VARCHAR                 -- S256
  expires_at      TIMESTAMP
  created_at      TIMESTAMP
```

### 4.18 Configuration

```sql
instance_settings
  key             VARCHAR PRIMARY KEY
  value           JSONB
  type            ENUM (string, integer, boolean, json)
  category        VARCHAR                       -- general, limits, federation, media, registration, etc.
  description     TEXT
  updated_by      UUID REFERENCES identities
  updated_at      TIMESTAMP

email_templates
  id              UUID PRIMARY KEY
  key             VARCHAR UNIQUE                -- "welcome", "password_reset", etc.
  subject         VARCHAR                       -- with {placeholder} support
  body_html       TEXT
  body_text       TEXT
  updated_by      UUID REFERENCES identities
  updated_at      TIMESTAMP
```

### 4.19 Video Stream Views

```sql
stream_views
  id              UUID PRIMARY KEY
  post_id         UUID REFERENCES posts
  identity_id     UUID REFERENCES identities    -- nullable for logged-out
  watch_duration  FLOAT                         -- seconds
  total_duration  FLOAT
  completed       BOOLEAN DEFAULT false
  replayed        BOOLEAN DEFAULT false
  source          ENUM (feed, profile, trending, direct_link)
  created_at      TIMESTAMP
```

### 4.20 Page Branding

```sql
page_branding
  identity_id     UUID PRIMARY KEY REFERENCES organizations
  theme_color     VARCHAR
  cover_image_id  UUID REFERENCES media
  custom_css      TEXT                          -- sanitized, scoped
  logo_id         UUID REFERENCES media
  layout_preference JSONB
  updated_at      TIMESTAMP
```

### 4.21 Donations & Funding

```sql
instance_funding
  id              UUID PRIMARY KEY
  platform        ENUM (stripe, paypal, bitcoin, ethereum, custom)
  config          JSONB                         -- API keys, wallet addresses (encrypted)
  enabled         BOOLEAN DEFAULT false
  display_text    VARCHAR
  goal_amount     DECIMAL
  current_amount  DECIMAL DEFAULT 0
  updated_at      TIMESTAMP

donations
  id              UUID PRIMARY KEY
  donor_id        UUID REFERENCES identities    -- nullable for anonymous
  amount          DECIMAL
  currency        VARCHAR(3)
  platform        VARCHAR
  transaction_id  VARCHAR
  created_at      TIMESTAMP
```

### 4.22 Backup

```sql
backup_jobs
  id              UUID PRIMARY KEY
  type            ENUM (full, settings_only, users_only)
  status          ENUM (pending, running, completed, failed)
  file_path       VARCHAR
  encryption_key_hash VARCHAR                   -- hash only, never the key
  file_size       BIGINT
  started_at      TIMESTAMP
  completed_at    TIMESTAMP
  initiated_by    UUID REFERENCES identities
```

### 4.23 Algorithmic Feed Signals

```sql
user_interaction_signals
  identity_id         UUID REFERENCES identities
  target_identity_id  UUID REFERENCES identities
  interaction_count   INTEGER DEFAULT 0
  last_interaction    TIMESTAMP
  content_tags        JSONB                     -- topics they engage with
  UNIQUE (identity_id, target_identity_id)
```

---

## 5. API Surface

All endpoints prefixed with `/api/v1/`. URL versioning.

### 5.1 Authentication

```
POST   /api/v1/auth/register              Register new account
POST   /api/v1/auth/login                 Login (returns JWT access + refresh token)
POST   /api/v1/auth/refresh               Refresh access token
POST   /api/v1/auth/logout                Revoke tokens
POST   /api/v1/auth/confirm               Confirm email
POST   /api/v1/auth/password/reset        Request password reset
POST   /api/v1/auth/password/change       Change password
POST   /api/v1/auth/2fa/setup             Set up 2FA
POST   /api/v1/auth/2fa/verify            Verify 2FA code
DELETE /api/v1/auth/2fa                    Disable 2FA
```

### 5.2 Accounts

```
GET    /api/v1/accounts/:id               Get account
PATCH  /api/v1/accounts/update_credentials Update own profile
DELETE /api/v1/accounts/delete            Delete account (30-day cooling off)
GET    /api/v1/accounts/:id/statuses      Get account's posts
GET    /api/v1/accounts/:id/followers     Get followers
GET    /api/v1/accounts/:id/following     Get following
GET    /api/v1/accounts/relationships     Get relationships with given accounts
POST   /api/v1/accounts/:id/follow        Follow
POST   /api/v1/accounts/:id/unfollow      Unfollow
POST   /api/v1/accounts/:id/block         Block
POST   /api/v1/accounts/:id/unblock       Unblock
POST   /api/v1/accounts/:id/mute          Mute
POST   /api/v1/accounts/:id/unmute        Unmute
GET    /api/v1/accounts/search            Search accounts
```

### 5.3 Posts (Statuses)

```
POST   /api/v1/statuses                   Create post
GET    /api/v1/statuses/:id               Get post
DELETE /api/v1/statuses/:id               Delete post
PUT    /api/v1/statuses/:id               Edit post (within 24h)
GET    /api/v1/statuses/:id/history       Get edit history
POST   /api/v1/statuses/:id/react         React to post
DELETE /api/v1/statuses/:id/react         Remove reaction
POST   /api/v1/statuses/:id/boost         Boost post
DELETE /api/v1/statuses/:id/boost         Remove boost
POST   /api/v1/statuses/:id/bookmark      Bookmark post
DELETE /api/v1/statuses/:id/bookmark      Remove bookmark
POST   /api/v1/statuses/:id/pin           Pin post
DELETE /api/v1/statuses/:id/pin           Unpin post
GET    /api/v1/statuses/:id/context       Get thread (ancestors + descendants)
GET    /api/v1/statuses/:id/reactions      Get reactions with actors
GET    /api/v1/statuses/:id/boosts        Get who boosted
POST   /api/v1/statuses/schedule          Schedule a post
```

### 5.4 Timelines

```
GET    /api/v1/timelines/home             Home feed (chronological or algorithmic)
GET    /api/v1/timelines/public           Public/global feed
GET    /api/v1/timelines/tag/:hashtag     Hashtag feed
GET    /api/v1/timelines/list/:id         List feed
GET    /api/v1/timelines/group/:id        Group feed
GET    /api/v1/timelines/streams          Video streams feed
```

### 5.5 Streaming (Real-time)

```
GET    /api/v1/streaming/user             SSE: own notifications + home feed
GET    /api/v1/streaming/public           SSE: public feed
GET    /api/v1/streaming/hashtag/:tag     SSE: hashtag feed
GET    /api/v1/streaming/list/:id         SSE: list feed
GET    /api/v1/streaming/group/:id        SSE: group feed
WS     /api/v1/streaming/direct           WebSocket: DM conversations
```

### 5.6 Conversations (DMs)

```
GET    /api/v1/conversations              List conversations
GET    /api/v1/conversations/:id          Get conversation
POST   /api/v1/conversations              Start new conversation
POST   /api/v1/conversations/:id/messages Send message
GET    /api/v1/conversations/:id/messages Get messages (paginated)
PUT    /api/v1/conversations/:id/messages/:mid Edit message
DELETE /api/v1/conversations/:id/messages/:mid Delete message
POST   /api/v1/conversations/:id/read     Mark as read
PATCH  /api/v1/conversations/:id/settings Mute/unmute conversation
GET    /api/v1/dm_preferences             Get DM privacy settings
PATCH  /api/v1/dm_preferences             Update DM privacy settings
```

### 5.7 Groups

```
GET    /api/v1/groups                     List groups (search/browse)
POST   /api/v1/groups                     Create group
GET    /api/v1/groups/:id                 Get group
PATCH  /api/v1/groups/:id                 Update group
DELETE /api/v1/groups/:id                 Delete group
POST   /api/v1/groups/:id/join            Join / apply to join
POST   /api/v1/groups/:id/leave           Leave group
GET    /api/v1/groups/:id/members         List members
POST   /api/v1/groups/:id/invite          Invite user
GET    /api/v1/groups/:id/applications    List applications (admin)
POST   /api/v1/groups/:id/applications/:aid/approve  Approve
POST   /api/v1/groups/:id/applications/:aid/reject   Reject
PATCH  /api/v1/groups/:id/members/:mid    Update member role
DELETE /api/v1/groups/:id/members/:mid    Remove member
GET    /api/v1/groups/:id/screening       Get screening config (admin)
PATCH  /api/v1/groups/:id/screening       Update screening config (admin)
```

### 5.8 Media

```
POST   /api/v1/media                      Upload media
GET    /api/v1/media/:id                  Get media metadata
PUT    /api/v1/media/:id                  Update alt text
```

### 5.9 Lists

```
GET    /api/v1/lists                      List all lists
POST   /api/v1/lists                      Create list
GET    /api/v1/lists/:id                  Get list
PATCH  /api/v1/lists/:id                  Update list
DELETE /api/v1/lists/:id                  Delete list
GET    /api/v1/lists/:id/accounts         Get list members
POST   /api/v1/lists/:id/accounts         Add accounts to list
DELETE /api/v1/lists/:id/accounts         Remove accounts from list
```

### 5.10 Notifications

```
GET    /api/v1/notifications              List notifications (paginated, filterable)
GET    /api/v1/notifications/:id          Get notification
POST   /api/v1/notifications/clear        Mark all as read
POST   /api/v1/notifications/:id/read     Mark one as read
GET    /api/v1/notification_preferences   Get preferences
PATCH  /api/v1/notification_preferences   Update preferences
```

### 5.11 Search

```
GET    /api/v1/search                     Unified search (accounts, posts, hashtags, groups)
                                          Params: q, type, limit, offset
```

### 5.12 Polls

```
GET    /api/v1/polls/:id                  Get poll
POST   /api/v1/polls/:id/votes            Cast vote
```

### 5.13 Custom Emoji

```
GET    /api/v1/custom_emojis              List instance custom emoji
```

### 5.14 Instance

```
GET    /api/v1/instance                   Instance info (name, description, stats, rules)
GET    /api/v1/instance/peers             List known federated instances
GET    /api/v1/instance/rules             Instance rules
```

### 5.15 Bookmarks

```
GET    /api/v1/bookmarks                  List bookmarks
```

### 5.16 Trends

```
GET    /api/v1/trends/tags                Trending hashtags
GET    /api/v1/trends/statuses            Trending posts
GET    /api/v1/trends/links               Trending links
```

### 5.17 Import/Export

```
POST   /api/v1/export                     Request data export (async)
GET    /api/v1/export/:id                 Download export
POST   /api/v1/import                     Import data (follows, blocks, etc.)
```

### 5.18 Admin API

```
-- Prefixed with /api/v1/admin/

GET    /admin/accounts                    List accounts (with filters)
GET    /admin/accounts/:id                Get account detail
POST   /admin/accounts/:id/action         Perform action (warn, suspend, unsuspend, delete)
GET    /admin/reports                     List reports
GET    /admin/reports/:id                 Get report
POST   /admin/reports/:id/resolve         Resolve report
POST   /admin/reports/:id/assign          Assign report
GET    /admin/audit_log                   View audit log (immutable)
GET    /admin/instance/settings           Get all settings
PATCH  /admin/instance/settings           Update settings
GET    /admin/federation/peers            Federation dashboard
GET    /admin/federation/policies         List domain policies
POST   /admin/federation/policies         Add domain policy
DELETE /admin/federation/policies/:domain Remove domain policy
GET    /admin/federation/queue            Delivery queue status
GET    /admin/custom_emojis               List custom emoji
POST   /admin/custom_emojis               Create custom emoji
DELETE /admin/custom_emojis/:id           Delete custom emoji
GET    /admin/email_templates             List email templates
PATCH  /admin/email_templates/:id         Update email template
GET    /admin/content_filters             List content filters
POST   /admin/content_filters             Create content filter
DELETE /admin/content_filters/:id         Delete content filter
GET    /admin/banned_domains              List banned domains
POST   /admin/banned_domains              Add banned domain
DELETE /admin/banned_domains/:domain      Remove banned domain
POST   /admin/relays                      Add relay
DELETE /admin/relays/:id                  Remove relay
GET    /admin/stats                       Instance statistics
POST   /admin/backup                      Create backup
GET    /admin/backups                     List backups
GET    /admin/backups/:id/download        Download backup
POST   /admin/backups/:id/restore         Restore from backup (requires encryption key)
```

### 5.19 OAuth2

```
GET    /oauth/authorize                   Authorization page
POST   /oauth/token                       Exchange code for token
POST   /oauth/revoke                      Revoke token
GET    /api/v1/apps                       List registered apps
POST   /api/v1/apps                       Register new app
```

### 5.20 Subscriptions & Verification

```
GET    /api/v1/subscriptions/plans        Available plans
POST   /api/v1/subscriptions              Subscribe to premium
GET    /api/v1/subscriptions/current      Current subscription
DELETE /api/v1/subscriptions              Cancel subscription
POST   /api/v1/verification/apply         Apply for verification
GET    /api/v1/verification/status        Check verification status
```

### Pagination

All list endpoints use cursor-based pagination:
```
GET /api/v1/timelines/home?cursor=abc123&limit=20
Response headers:
  Link: <url?cursor=next123>; rel="next", <url?cursor=prev456>; rel="prev"
```

---

## 6. Authentication & Authorization

### 6.1 User Auth

- **Registration**: Email + password. Email confirmation required. PoW challenge on registration endpoint.
- **Login**: Email + password → JWT access token (15 min) + opaque refresh token (stored server-side, 30 days)
- **2FA**: TOTP (RFC 6238) via authenticator app. Recovery codes generated on setup.
- **Sessions**: Track active sessions. Allow revoking individual sessions.
- **Password**: bcrypt with cost factor 12. Minimum 8 characters.

### 6.2 OAuth2 + PKCE

For third-party apps:
1. App registers with instance → receives client_id + client_secret
2. App redirects user to `/oauth/authorize` with PKCE code_challenge
3. User approves scopes → redirect back with authorization code
4. App exchanges code + code_verifier → access token + refresh token

### 6.3 API Scopes

```
read                    Read all data
read:accounts           Read profiles
read:statuses           Read posts
read:notifications      Read notifications
read:groups             Read group info
read:search             Use search
write                   Write all data
write:statuses          Create/edit/delete posts
write:media             Upload media
write:favourites        React to posts
write:follows           Follow/unfollow
write:groups            Group management
write:conversations     Send DMs
push                    Receive push notifications
admin:read              Admin read access
admin:write             Admin write access
```

### 6.4 HMAC Request Signing (Optional)

For high-security API integrations:
1. Admin generates API key pair (client_id + signing_secret) for the integration
2. Client signs: `HMAC-SHA256(secret, method + path + timestamp + SHA256(body))`
3. Sends as `X-Signature` header with `X-Timestamp` header
4. Server verifies. Rejects if timestamp > 5 min old (replay prevention)

---

## 7. ActivityPub Federation

### 7.1 Endpoints

```
GET  /.well-known/webfinger              WebFinger discovery
GET  /.well-known/nodeinfo               NodeInfo (instance metadata)
GET  /actors/:uuid                       Actor object
GET  /actors/:uuid/inbox                 Actor inbox (POST to deliver)
POST /actors/:uuid/inbox                 Receive activities
GET  /actors/:uuid/outbox                Actor outbox (paginated collection)
GET  /actors/:uuid/followers             Followers collection
GET  /actors/:uuid/following             Following collection
```

### 7.2 WebFinger

`GET /.well-known/webfinger?resource=acct:handle@domain`

Returns the UUID-based actor URL. When handle changes, WebFinger resolves the new handle to the same actor URL. Remote servers that cached the actor URL continue working.

### 7.3 Actor Representation

Each internal identity maps to an AP Actor:

```json
{
  "@context": ["https://www.w3.org/ns/activitystreams", ...],
  "id": "https://instance.com/actors/{uuid}",
  "type": "Person",
  "preferredUsername": "handle",
  "name": "Display Name",
  "summary": "<p>Bio HTML</p>",
  "inbox": "https://instance.com/actors/{uuid}/inbox",
  "outbox": "https://instance.com/actors/{uuid}/outbox",
  "followers": "https://instance.com/actors/{uuid}/followers",
  "following": "https://instance.com/actors/{uuid}/following",
  "publicKey": { ... },
  "icon": { ... },
  "image": { ... },
  "endpoints": { "sharedInbox": "https://instance.com/inbox" }
}
```

Organizations → `type: "Organization"`
Groups → `type: "Group"`

### 7.4 Supported Activities

**Outbound (publishing)**:
- `Create` (Note, Article, Question)
- `Update` (edited posts, profile updates)
- `Delete` (posts, accounts)
- `Follow` / `Accept` / `Reject`
- `Like` (standard likes)
- `EmojiReact` (custom reactions — Pleroma extension)
- `Announce` (boosts)
- `Block`
- `Flag` (reports)
- `Move` (actor migration)
- `Add` / `Remove` (pinned posts)

**Inbound (receiving)**:
All of the above, plus processing steps:
1. Verify HTTP signature
2. Check domain policy (allow/silence/suspend/block_media/force_nsfw)
3. Deduplicate (check federation_dedup table)
4. Validate payload structure
5. Store or update local representation
6. Trigger event pipeline via NATS

### 7.5 Object Mapping

| Internal | AP Object |
|----------|-----------|
| Text post | Note |
| Article post | Article |
| Poll | Question |
| Quote post | Note with `quoteUrl` extension |
| Video stream | Note with video attachment |
| Custom reactions | EmojiReact (Pleroma/Akkoma extension) |

### 7.6 HTTP Signatures

- Sign all outbound requests with the actor's private key (RSA-SHA256)
- Verify all inbound requests against the remote actor's public key
- Fetch remote actor's public key if not cached
- Key rotation: support both old and new keys during transition

### 7.7 Federation Delivery

1. Post created → determine recipients (followers, mentioned actors, group members)
2. Resolve recipient inboxes (batch by shared inbox where possible)
3. Queue delivery jobs in NATS
4. Worker signs and delivers to each inbox
5. On failure: exponential backoff retry (1min, 5min, 30min, 2hr, 12hr, 24hr, give up)
6. Track delivery status in `federation_deliveries`

### 7.8 Activity ID Format (Human-Readable)

```
https://instance.com/activities/{actor_uuid}/{action}/{target_uuid}/{timestamp}
```

Example: `https://instance.com/activities/a1b2c3/create/d4e5f6/20260321T140000Z`

Deduplication: hash `actor + action + target` — same actor performing same action on same target is a duplicate regardless of timestamp.

### 7.9 Actor Migration

Outgoing:
1. User sets up account on new instance
2. New account adds old account as `alsoKnownAs`
3. Old account sends `Move` activity with `target` pointing to new account
4. Old account enters redirect state (profile shows redirect, posts frozen)

Incoming:
1. Receive `Move` activity
2. Verify `alsoKnownAs` on new actor references old actor
3. Update local follow records (followers of old → follow new)
4. Cache redirect for display

---

## 8. Media Pipeline

### 8.1 Upload Flow

```
Client upload → API
  → Validate content-type (magic bytes, not extension)
  → Check file size against limits
  → Store in quarantine directory
  → ClamAV scan (clamd socket)
    → If infected: reject, delete, log
    → If clean: proceed
  → Strip ALL metadata (EXIF, original filename — store nothing from original)
  → Generate UUID filename
  → Process based on type:
    → Image: libvips resize, generate blurhash, create thumbnail
    → Video: ffmpeg probe → transcode to configured resolutions → extract thumbnail
  → Move to permanent storage (local or S3)
  → Create media record in database
  → Return media ID to client
```

### 8.2 Image Processing

- Resize to max configured dimensions (preserve aspect ratio)
- Strip color profiles, convert to sRGB
- Generate blurhash (20 components)
- Generate thumbnail (configurable size, default 400px wide)
- Output format: WebP (with JPEG fallback for compatibility)

### 8.3 Video Processing

- Probe source resolution with ffmpeg
- Transcode rules (admin configurable):
  - Source > 720p → create 720p + 480p variants
  - Source 481-720p → keep original + create 480p
  - Source ≤ 480p → keep original only
  - Always create 240p preview for low-bandwidth
- Container: MP4 (H.264 video, AAC audio) for maximum compatibility
- Extract thumbnail at 1-second mark (or configurable timestamp)
- Video streams (reels): enforce 9:16 aspect ratio, max configurable duration (default 90s)

### 8.4 Storage

- Configurable: local filesystem or S3-compatible (MinIO, AWS S3, etc.)
- Path structure: `/{content_type_prefix}/{year}/{month}/{uuid}.{ext}`
- Local: configurable base directory
- S3: configurable bucket, region, credentials
- **Cluster requirement**: S3 mandatory for multi-server deployments

### 8.5 Media Cleanup

- Soft-deleted post → mark media for cleanup
- Background job runs periodically (configurable interval)
- After retention period (configurable, default 30 days): delete media files from storage
- Orphaned media (uploaded but never attached to a post): clean up after 24 hours

---

## 9. Direct Messaging

### 9.1 Local DMs

- Finding/creating conversations: check if conversation between exact participant set exists, reuse or create
- Messages stored in `messages` table
- Read state tracked via `last_read_message_id` per participant
- Unread count: `COUNT(messages WHERE id > last_read_message_id)`
- Real-time delivery via WebSocket (`/api/v1/streaming/direct`)
- Typing indicators and read receipts via WebSocket events

### 9.2 Federated DMs

- Sent as AP `Create` activity with `to` field listing only recipient actor URIs
- Incoming federated DMs create local conversation with remote actor placeholder
- Remote actors can't see typing indicators or read receipts (no protocol support)

### 9.3 DM Privacy

- `dm_preferences` table controls who can initiate DMs
- Group DMs disabled by default, opt-in per user
- Incoming DMs from non-allowed senders → held in "message requests" (not rejected — prevents leaking preference info to federated servers)

### 9.4 E2EE (Post-MVP)

- Olm for 1:1 sessions, Megolm for group DM sessions
- Encryption applied at the content layer — transport and storage unchanged
- Key distribution via API endpoints
- Device keys registered on account setup
- Session key rotation on member change (group DMs)

---

## 10. Groups & Communities

### 10.1 Group Types

| Type | Federated | Discoverable | Who can see posts |
|------|-----------|-------------|-------------------|
| Public | Yes (Group actor) | Yes | Everyone |
| Private | Optional | Search only | Members only |
| Local-only | No | Instance only | Members only |

### 10.2 Join Policies

- **Open**: Instant join, no approval
- **Screening**: Auto-approve if criteria met (account age, profile image, question answers), otherwise queue for admin
- **Approval**: All applications queued for admin review
- **Invite-only**: Only members can invite, no public applications

### 10.3 Group Federation

- Public groups represented as AP `Group` actor
- When someone posts to the group, the group actor `Announce`s it to followers
- Remote users can follow the group actor
- Remote users can post to the group by addressing it
- Private group posts delivered to member inboxes only

### 10.4 Group Posts

- Posts with `group_id` set and `visibility: group`
- Delivered to group members (local) and group followers (federated, if public)
- Private group posts: addressed `to: [group_actor_uri]` with `cc: [members...]`

---

## 11. Feeds & Ranking

### 11.1 Feed Types

| Feed | Source | Default Sort |
|------|--------|-------------|
| Home | Followed accounts | User's choice: chronological or algorithmic |
| Public | All local public posts | Chronological |
| Group | Posts in a group | Chronological |
| List | Posts from list members | Chronological |
| Hashtag | Posts with specific tag | Chronological |
| Streams (Video) | video_stream posts | Algorithmic (engagement-based) |

### 11.2 Chronological Feed

Simple reverse-chronological from followed accounts. No ranking. Cached in Valkey. Invalidated on new post from followed account.

### 11.3 Algorithmic Feed

User opt-in. Ranking signals:

- **Interaction affinity** (40%): Weight by how often user interacts with this author (reactions, replies, boosts, profile views). Stored in `user_interaction_signals`.
- **Engagement velocity** (20%): How fast is this post gaining reactions/replies relative to its age
- **Content affinity** (15%): Does this post's hashtags/topics match what the user engages with
- **Social proximity** (10%): Friends-of-friends ranked higher
- **Freshness** (10%): Exponential time decay
- **Diversity injection** (5%): Force 10-20% of feed to be outside user's bubble

Background worker precomputes feed rankings. Cached in Valkey with TTL. Recomputed on significant events (new interactions from user, new high-engagement posts).

### 11.4 Feed Visibility Enforcement

Every feed query MUST:
1. Exclude posts from blocked/muted accounts
2. Exclude posts from suspended accounts
3. Filter by visibility rules (followers-only requires follow check)
4. Apply instance content policies
5. Apply content warnings/sensitive flags

---

## 12. Video Streams

### 12.1 What They Are

Short-form vertical video feed (like Reels/TikTok). Internally, a post with `post_type: video_stream`.

### 12.2 Constraints

- Vertical aspect ratio (9:16) enforced during upload
- Max duration: configurable (default 90 seconds)
- Auto-generated thumbnail at multiple timestamps (user picks or auto-select)

### 12.3 Discovery Algorithm

Ranking signals for the Streams feed:
- **Watch completion rate**: Strongest signal — if most viewers watch to the end
- **Replay rate**: Users re-watching = high quality content
- **Engagement rate**: Likes, comments, shares relative to view count
- **Alt text / captions**: Topic categorization for interest matching
- **User interaction history**: More from creators the user has watched before
- **Freshness**: Time decay, but slower than text (videos have longer shelf life)
- **Follow status**: Prioritize followed creators, mix in discovery content

### 12.4 View Tracking

Privacy-sensitive. Raw view logs purged after metrics computed. Aggregate only. Users can opt out of personalized recommendations.

---

## 13. Search & Trending

### 13.1 Search (OpenSearch)

Indexed entities:
- Posts (full-text on content, hashtags)
- Accounts (handle, display name, bio)
- Groups (name, description)
- Hashtags (name, usage count)

Features:
- Full-text search with stemming
- Fuzzy search (typo tolerance)
- Prefix search (autocomplete)
- Filtered by visibility (user can only find posts they're allowed to see)

### 13.2 Indexing Pipeline

Post created → NATS event → Search indexer worker → OpenSearch

Updates and deletes propagated the same way. Reindex command available for admin (`mix hybridsocial.search.reindex`).

### 13.3 Trending

Computed by background workers, cached in Valkey.

**Trending hashtags**: Top hashtags by usage velocity over configurable time window.
**Trending posts**: Top posts by engagement velocity.
**Trending links**: Top shared URLs by frequency.

**Manipulation resistance**:
- Account diversity requirement: N unique accounts to reach trending threshold
- Account age weighting: New accounts count less
- Interaction pattern detection: Coordinated behavior flagged
- Velocity caps: Max rise speed prevents artificial spikes
- Exponential decay curves
- Admin override: Force-remove from trending or pin to trending

---

## 14. Notifications

### 14.1 Types

follow, follow_request, reaction, boost, quote, reply, mention, poll_ended, group_invite, group_application, report (mod), admin

### 14.2 Delivery Channels

- **In-app**: SSE stream (`/api/v1/streaming/user`). Stored in `notifications` table.
- **Push**: FCM (Android) + APNs (iOS). Sent via background worker.
- **Email**: Via Swoosh. Configurable frequency: immediate, hourly digest, daily digest, never.

### 14.3 Preferences

Per-user, per-notification-type, per-channel configuration. Stored in `notification_preferences`.

---

## 15. Reactions & Custom Emoji

### 15.1 Reactions

7 default types: like, love, care, angry, sad, lol, wtf

Premium users: up to 14 custom reactions (7 default + 7 instance-defined or user-defined).

One reaction per user per post. Changing reaction replaces the previous one.

**Federation**:
- `like` → AP `Like` activity
- All others → `EmojiReact` activity (Pleroma/Akkoma extension)
- Incoming AP `Like` → maps to internal `like` type
- Servers that don't support `EmojiReact` ignore non-like reactions

### 15.2 Custom Emoji (Instance-level)

Custom emoji for use in post text (`:shortcode:` syntax). Managed via admin panel.

Federated via AP `Emoji` tag type. Compatible with Mastodon, Pleroma, Misskey.

---

## 16. Moderation & Safety

### 16.1 Reporting

Users can report posts, accounts, conversations, groups. Reports include category and description. Reports optionally federated as AP `Flag` activity.

### 16.2 Report Workflow

1. Report submitted → enters queue
2. Assigned to moderator (manually or auto-assign)
3. Moderator reviews context (reported content, user history, prior reports)
4. Actions: dismiss, warn user, delete content, suspend account, ban
5. Resolution logged in audit trail

### 16.3 Content Filters

Word/phrase/regex patterns with configurable actions (flag, reject, replace). Applied at content creation time, before storage.

### 16.4 Domain Management

- Email domain bans (block registration from disposable email providers)
- Federation domain policies (allow, silence, suspend, block_media, force_nsfw)

### 16.5 Audit Log

Immutable. Every moderation and admin action logged with: who, what, when, why (reason), target, before/after state. Cannot be edited or deleted.

### 16.6 Moderation Webhooks

Configurable webhooks for moderation events: new report, report resolved, user suspended, content removed, appeal submitted. Enables integration with external moderation tools.

---

## 17. Pages & Organizations

- Modeled as actors with `type: organization`
- Separate `organizations` table with ownership and role management
- Roles: admin, editor, moderator
- Pages can: publish posts, manage followers, act as brands
- Branding: custom theme color, cover image, logo, scoped CSS
- Federated as AP `Organization` actor

---

## 18. Verification & Premium

### 18.1 Verification

- Types: manual (admin-granted), domain (prove domain ownership), paid
- Badge displayed on profile
- Exposed in AP actor metadata

### 18.2 Premium Features

| Feature | Free | Premium |
|---------|------|---------|
| Post length | Standard (configurable, default 5000) | Extended (configurable, default 10000) |
| Reactions | 7 default | Up to 14 |
| Markdown in posts | No (plain text only) | Yes |
| Video upload duration | Standard (configurable) | Extended |
| Video resolution | Up to 720p | Up to 1080p |
| Scheduled posts | No | Yes |
| Post analytics | No | Yes (reach, boosts, engagement) |
| Profile themes | No | Yes |

All limits configurable via admin panel.

---

## 19. Monetization & Donations

### 19.1 Subscriptions

Payment providers: Stripe, PayPal, Crypto (wallet addresses).

Stripe/PayPal: use their subscription APIs for recurring billing.
Crypto: manual verification or use a payment processor.

### 19.2 Donations

Instance funding page with:
- Goal progress bar (optional)
- Multiple payment methods (admin-configurable)
- Anonymous donations supported
- Transaction log for transparency

---

## 20. Admin Panel

Full scope:

- **Dashboard**: User count, post count, federation stats, media storage, active connections, error rates
- **User Management**: Search, view, suspend, unsuspend, delete, force password reset, approve registrations
- **Moderation**: Report queue, content filters, banned domains, IP blocks, keyword filters
- **Federation**: Connected instances, domain policies, relay management, delivery queue, remote actor cache
- **Content**: Trending management, custom emoji, announcement banners
- **Settings**: All instance settings (database-backed, runtime-configurable)
- **Email**: Template customization (HTML + placeholders)
- **Audit Log**: Immutable action history
- **Backups**: Create, download, restore

---

## 21. Configuration System

### 21.1 Layered Priority

```
1. Database (admin-configurable at runtime) — HIGHEST
2. Environment variables (deployment-level overrides)
3. Code defaults — LOWEST
```

### 21.2 Implementation

Settings stored in `instance_settings` table. Loaded into ETS (Elixir in-memory store) on boot and on change. Reads are in-memory (no DB query per request). Admin updates → write to DB → update ETS → immediate effect.

Environment variables for infrastructure only: `DATABASE_URL`, `SECRET_KEY_BASE`, `S3_*`, `SMTP_*`, etc.

### 21.3 Setting Categories

general, limits, registration, federation, media, email, security, premium, appearance

---

## 22. Email System

### 22.1 Provider Support

SMTP and Resend via Swoosh adapters. Configurable at runtime.

### 22.2 Email Types

- Account confirmation
- Password reset
- Login notification (new device/IP)
- Notification digests (configurable frequency)
- Admin alerts
- Account deletion confirmation

### 22.3 Templates

Admin-customizable HTML templates with `{placeholder}` syntax. Stored in database. Shipped with sensible defaults. Reset-to-default available.

---

## 23. Security

### 23.1 Transport

- TLS everywhere (Caddy auto-provisions Let's Encrypt certificates)
- Coraza WAF with OWASP CRS (tuned for AP endpoints)
- HSTS, CSP, X-Frame-Options headers

### 23.2 Authentication

- bcrypt password hashing (cost factor 12)
- JWT access tokens (15 min TTL)
- Opaque refresh tokens (server-side, 30 day TTL)
- TOTP 2FA with recovery codes
- Session tracking and revocation

### 23.3 Rate Limiting

**Application level** (token bucket):
- Authenticated: 300 req/min normal, 50 burst allowance
- Degraded (abuse detected): 60 req/min
- Blocked (sustained abuse): temporary ban

**PoW** (Proof of Work) on abuse-prone anonymous endpoints:
- Account registration
- Password reset
- Anonymous search

**WAF level**: Coraza with OWASP CRS rules

### 23.4 Input Validation

- Content sanitization on all user input
- HTML allowlist for rendered content (no script, no style, no event handlers)
- File upload validation by magic bytes (never trust extensions)
- SSRF prevention in link preview fetcher (reject private IP ranges)
- SQL injection prevention via Ecto parameterized queries
- XSS prevention via HTML sanitization and CSP headers

### 23.5 Federation Security

- HTTP signature verification on all inbound activities
- Domain policy enforcement
- Rate limiting on federation inbox
- Payload size limits
- JSON-LD validation

### 23.6 Media Security

- ClamAV scanning before storage
- EXIF stripping
- Content-type verification via magic bytes
- File size limits
- No original filename storage

---

## 24. Data Portability

### 24.1 Export

Async job. Produces a `.tar.gz` archive containing:
- `outbox.json` — All posts as AP objects
- `following.json` — Follow list
- `followers.json` — Follower list (informational)
- `blocks.json` — Block list
- `mutes.json` — Mute list
- `bookmarks.json` — Bookmarks
- `lists.json` — Lists with members
- `profile.json` — Bio, settings, preferences
- `media/` — All uploaded media files

CSV format available for simple lists (follows, blocks, mutes) for Mastodon compatibility.

### 24.2 Import

Support importing:
- Follows list (CSV or JSON)
- Blocks list
- Mutes list
- Bookmarks

Post import from other platforms: best-effort, map to internal format.

### 24.3 Account Deletion

1. User requests deletion via frontend
2. 30-day cooling-off period (can cancel)
3. After 30 days: background job executes
4. Send AP `Delete` actor activity to all known federated servers
5. Purge or anonymize all local data
6. Remove media from storage
7. Replace post attributions with "deleted user" placeholder for posts others replied to
8. Log deletion in audit trail (that a deletion occurred, not the deleted data)

---

## 25. Internationalization

### 25.1 Approach

Backend returns error codes/keys. Frontend translates using locale JSON files.

### 25.2 Locale Files

```
frontend/src/locales/
  en.json
  ar.json
  fr.json
  ...
```

Structure: flat namespaced keys with `{placeholder}` interpolation.

### 25.3 Community Translation

Weblate instance (self-hosted or hosted). Connected to frontend repo. Translators submit via Weblate UI. CI validates JSON structure. New languages = new file + entry in supported languages config.

### 25.4 RTL Support

Frontend responsibility. Detect text direction from first strong Unicode character. Set `dir="rtl"` or `dir="ltr"` on containers. Use CSS `text-align: start`. Mixed-direction handled by Unicode Bidi algorithm.

### 25.5 Language Tagging

Posts include `language` field. Used for AP `contentMap` and for filtering posts by language in feeds.

---

## 26. Accessibility

### 26.1 Target

WCAG 2.1 AA compliance.

### 26.2 Requirements

- Full keyboard navigation for all features
- Screen reader compatibility (ARIA labels, semantic HTML)
- Color contrast ratios (4.5:1 minimum for text)
- Visible focus indicators
- Alt text on all images (media model supports it)
- Video captions support (user-uploaded)
- Reduced motion support (`prefers-reduced-motion` media query)
- Proper heading hierarchy
- Form labels and error messages

Built into the component library from day one.

---

## 27. Testing Strategy

### 27.1 Unit Tests (ExUnit)

Test individual functions: visibility checks, permission logic, content sanitization, trending algorithm, ACL evaluation. Use Mox for mocking external dependencies. Fast, run in milliseconds.

### 27.2 Integration Tests (ExUnit + Ecto Sandbox)

Full request → response cycles through Phoenix endpoints. Ecto SQL sandbox for database isolation (each test in a transaction that rolls back). Test OAuth2 flows, API endpoints, permission enforcement.

### 27.3 Federation Conformance Tests

Two instances of the app in test (different ports). Test: follow flow, post federation, boost/reaction federation, delete propagation, block behavior, signature verification, tampered payload rejection.

### 27.4 Property-Based Tests (StreamData)

Random post content → verify sanitization always produces safe output. Random permission combinations → verify no unauthorized access. Edge case discovery for visibility and ranking logic.

### 27.5 Load Tests (k6)

Simulate concurrent users. Test feed endpoints, WebSocket connections, federation delivery under load. Run separately from CI (manual or scheduled).

### 27.6 Test Structure

```
test/
  hybridsocial/
    accounts/         # user, org, identity logic
    social/           # posts, reactions, boosts, polls
    messaging/        # DMs, conversations
    federation/       # AP processing, signatures
    moderation/       # reports, filters, blocks
    feeds/            # feed generation, ranking
    search/           # indexing, querying
    media/            # upload, processing
    groups/           # membership, screening
  hybridsocial_web/
    controllers/      # API endpoint tests
    channels/         # WebSocket/SSE tests
  federation/
    conformance/      # cross-instance tests
  support/
    factories.ex      # test data builders (ex_machina)
    fixtures/         # sample AP payloads
```

---

## 28. CI/CD Pipeline

### 28.1 GitHub Actions Workflow

```
Stages:

1. Build & Check
   - mix deps.get
   - mix compile --warnings-as-errors
   - mix format --check-formatted
   - mix credo --strict (static analysis)
   - mix dialyzer (type checking)

2. Test
   - Start services: PostgreSQL, Valkey, OpenSearch, NATS
   - mix ecto.create && mix ecto.migrate
   - mix test --cover
   - Upload coverage report

3. Security
   - mix deps.audit (vulnerable dependency check)
   - mix sobelow (Phoenix security scanner)

4. Build Docker Image (main branch / tags only)
   - Multi-stage Dockerfile (build + release)
   - Push to container registry

5. Deploy
   - Staging: automatic on main branch
   - Production: manual approval gate on tags
```

### 28.2 Docker Build

Multi-stage Dockerfile:
- Stage 1: Elixir build environment, compile release
- Stage 2: Minimal runtime image (Debian slim), copy release
- Result: Small image, fast startup, no Elixir/Erlang installation needed

---

## 29. Deployment

### 29.1 Docker Compose (Single Server)

```yaml
services:
  app:            # Phoenix API + workers (single Elixir node runs all)
  postgresql:     # Database
  valkey:         # Cache
  opensearch:     # Search
  nats:           # Message broker
  caddy:          # Reverse proxy + TLS + Coraza WAF
```

### 29.2 Minimum Requirements (Single Server)

- 4+ CPU cores
- 8+ GB RAM
- 50+ GB storage (more for media if stored locally)
- S3-compatible storage recommended for media

### 29.3 Production Checklist

- [ ] TLS configured (Caddy auto-provisions)
- [ ] Database backups scheduled
- [ ] Media storage configured (S3 recommended)
- [ ] Email provider configured
- [ ] WAF rules tuned (AP endpoint exclusions)
- [ ] Rate limiting configured
- [ ] Admin account created
- [ ] Instance settings configured
- [ ] Federation tested with a known instance
- [ ] Monitoring/alerting set up

---

## 30. Scaling & Clustering

### 30.1 When to Scale

- Sustained CPU > 80% on app server
- Database connection pool exhausted
- Response times degrading
- WebSocket/SSE connection limits reached

### 30.2 Cluster Architecture

```
Load Balancer (Caddy + Coraza)     — 1+ server
App servers (Phoenix/BEAM)         — 2+ servers (BEAM clustering via libcluster)
PostgreSQL                         — 1 primary + read replicas
Valkey                             — Cluster mode
OpenSearch                         — Cluster
NATS                               — Cluster (built-in)
```

### 30.3 Migration Path

Single server → cluster migration documented in operational guide. Key steps:
1. Migrate media to S3 (prerequisite)
2. Provision new servers
3. Set up PostgreSQL replication
4. Configure BEAM clustering (libcluster, shared cookie)
5. Brief maintenance window for final cutover
6. Verify and decommission old server

### 30.4 What Doesn't Change

Application code is the same. BEAM clustering, Phoenix PubSub, and ETS replication handle distribution transparently. Only deployment configuration changes.

---

## 31. Backup & Recovery

### 31.1 Database Backup

Internal backup system:
1. Admin triggers via admin panel
2. Background worker runs `pg_dump`
3. Compress with gzip
4. Encrypt with AES-256-GCM (admin provides passphrase)
5. Store locally or push to configured S3
6. **Passphrase never stored** — only hash for verification during restore

External backup (optional):
- JetBackup5 or custom scripts for full server backup
- S3 versioning for media protection

### 31.2 Restore

1. Admin uploads backup + provides passphrase
2. Verify passphrase hash
3. Decrypt → verify integrity
4. `pg_restore` into database
5. Reindex OpenSearch
6. Rebuild Valkey caches

### 31.3 Media

- S3: handled by S3 versioning/replication (no application-level backup needed)
- Local: include in external server backup (not in internal database backup)

---

## 32. Build Order

Phased approach from MVP to full platform.

### Phase 1: Foundation (Weeks 1-4)

- [ ] Project scaffolding (Phoenix, Ecto, Docker Compose)
- [ ] Database schema and migrations
- [ ] Identity/account system (registration, login, JWT, 2FA)
- [ ] Basic user profiles (CRUD, avatar, header)
- [ ] OAuth2 provider
- [ ] Configuration system (ETS-backed DB settings)
- [ ] CI/CD pipeline

### Phase 2: Core Social (Weeks 5-8)

- [ ] Posts (create, edit, delete, soft delete, revisions)
- [ ] Social graph (follow, block, mute)
- [ ] Reactions (7 types)
- [ ] Boosts and quote posts
- [ ] Chronological home feed
- [ ] Public timeline
- [ ] Post visibility enforcement
- [ ] Media upload pipeline (libvips, ffmpeg, ClamAV, S3)
- [ ] Content sanitization

### Phase 3: Federation (Weeks 9-12)

- [ ] WebFinger endpoint
- [ ] Actor endpoints (profile, inbox, outbox, followers, following)
- [ ] HTTP signature signing and verification
- [ ] Outbox: Create, Update, Delete, Follow, Like, Announce, Block
- [ ] Inbox processing for all activity types
- [ ] Federation delivery queue (NATS workers, retry logic)
- [ ] Remote actor resolution and caching
- [ ] Deduplication
- [ ] Instance policies (allow, silence, suspend, block_media, force_nsfw)
- [ ] Federation conformance tests

### Phase 4: Communities (Weeks 13-16)

- [ ] Groups (public, private, local-only)
- [ ] Group membership, roles, screening, auto-approval
- [ ] Group federation (Group actor)
- [ ] Pages/organizations with roles
- [ ] Page branding
- [ ] Lists
- [ ] Bookmarks
- [ ] Polls
- [ ] Hashtag extraction and indexing
- [ ] Pinned posts

### Phase 5: Messaging & Real-time (Weeks 17-20)

- [ ] DM conversations (1:1 and group)
- [ ] DM privacy preferences
- [ ] WebSocket for DMs (typing indicators, read receipts, delivery status)
- [ ] SSE for feeds and notifications
- [ ] Notification system (in-app, push, email)
- [ ] Notification preferences
- [ ] Email system (Swoosh, templates, SMTP + Resend)

### Phase 6: Discovery & Intelligence (Weeks 21-24)

- [ ] OpenSearch integration
- [ ] Full-text search (posts, accounts, groups, hashtags)
- [ ] Trending computation (posts, hashtags, links)
- [ ] Manipulation resistance
- [ ] Algorithmic feed (interaction signals, ranking)
- [ ] Video Streams feed and discovery
- [ ] Link preview / OpenGraph fetcher
- [ ] Custom emoji

### Phase 7: Moderation & Admin (Weeks 25-28)

- [ ] Report/flagging system
- [ ] Moderation workflow (queue, assign, actions)
- [ ] Content filters (word, phrase, regex)
- [ ] Banned domains (email, federation)
- [ ] Audit log (immutable)
- [ ] Moderation webhooks
- [ ] Admin panel API (all endpoints)
- [ ] Admin dashboard (stats, federation, users)
- [ ] Instance settings UI
- [ ] Email template management

### Phase 8: Premium & Polish (Weeks 29-32)

- [ ] Verification system
- [ ] Premium subscriptions (Stripe, PayPal)
- [ ] Premium feature gating
- [ ] Donation system (fiat + crypto)
- [ ] Data export/import
- [ ] Actor migration (Move activity)
- [ ] Account deletion (30-day cooling off, GDPR)
- [ ] Scheduled posts
- [ ] Rate limiting + PoW
- [ ] HMAC API signing
- [ ] Backup system (encrypted, admin-triggered)

### Phase 9: Frontend (Parallel Track)

- [ ] SvelteKit project setup
- [ ] Component library (accessible, animated)
- [ ] Auth flows (login, register, 2FA)
- [ ] Feed views (home, public, group, list, hashtag)
- [ ] Post composer (markdown for premium, plain text for free)
- [ ] Post interactions (reactions, boost, quote, bookmark)
- [ ] Profile pages
- [ ] Group pages
- [ ] DM interface
- [ ] Notification center
- [ ] Search
- [ ] Video Streams player
- [ ] Admin panel UI
- [ ] Settings pages
- [ ] Infinite scroll, skeleton loading, animations
- [ ] i18n (Weblate integration)
- [ ] RTL support
- [ ] WCAG 2.1 AA compliance
- [ ] PWA support

### Phase 10: Mobile (After Web Stable)

- [ ] Flutter project setup
- [ ] Shared API client
- [ ] Core screens (feed, profile, compose, notifications)
- [ ] Push notifications (FCM + APNs)
- [ ] DM with WebSocket
- [ ] Video Streams player
- [ ] Offline support (basic caching)

---

## Appendix A: Configurable Settings Reference

All settings stored in database, editable at runtime via admin panel.

| Category | Setting | Default |
|----------|---------|---------|
| General | Instance name | "HybridSocial" |
| General | Instance description | "" |
| General | Contact email | "" |
| Limits | Max post length (free) | 5000 |
| Limits | Max post length (premium) | 10000 |
| Limits | Max media per post | 4 |
| Limits | Max image file size | 10 MB |
| Limits | Max video file size | 100 MB |
| Limits | Max video duration | 300 seconds |
| Limits | Max stream (reel) duration | 90 seconds |
| Limits | Post edit window | 86400 seconds (24h) |
| Media | Storage backend | "local" |
| Media | Video resolutions | ["720p", "480p", "240p"] |
| Media | Image max dimensions | 4096x4096 |
| Registration | Mode | "open" |
| Registration | Require email confirmation | true |
| Registration | PoW difficulty | 16 bits |
| Federation | Enabled | true |
| Federation | Auto-accept follows | false |
| Federation | Deliver to shared inboxes | true |
| Security | Rate limit (authenticated) | 300/min |
| Security | Rate limit (anonymous) | 60/min |
| Security | Rate limit (federation inbox) | 100/min |
| Security | Max login attempts | 5 per 15 min |
| Premium | Enabled | false |
| Premium | Extra reactions count | 7 |
| Trending | Min accounts for trending | 3 |
| Trending | Computation interval | 300 seconds |
| Trending | History window | 86400 seconds |

---

## Appendix B: Environment Variables (Infrastructure Only)

```
DATABASE_URL=postgresql://user:pass@host:5432/hybridsocial
SECRET_KEY_BASE=<64+ char random string>
VALKEY_URL=redis://host:6379
NATS_URL=nats://host:4222
OPENSEARCH_URL=http://host:9200

S3_BUCKET=hybridsocial-media
S3_REGION=us-east-1
S3_ACCESS_KEY_ID=xxx
S3_SECRET_ACCESS_KEY=xxx
S3_ENDPOINT=https://s3.amazonaws.com  (or MinIO URL)

SMTP_HOST=smtp.example.com  (fallback if not set in DB)
SMTP_PORT=587
SMTP_USER=xxx
SMTP_PASS=xxx

RESEND_API_KEY=xxx  (fallback if not set in DB)

PHX_HOST=yourdomain.com
PHX_PORT=4000
RELEASE_NODE=hybridsocial@hostname  (for BEAM clustering)
RELEASE_COOKIE=shared-cluster-secret  (for BEAM clustering)
```

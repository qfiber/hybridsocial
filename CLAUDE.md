# HybridSocial

Decentralized social networking platform built on ActivityPub.

## Tech Stack

- **Backend**: Elixir / Phoenix
- **Frontend**: SvelteKit
- **Mobile**: Flutter
- **Database**: PostgreSQL
- **Cache**: Valkey
- **Search**: OpenSearch
- **Message Broker**: NATS JetStream
- **Media**: libvips (images), ffmpeg (video), ClamAV (scanning)
- **Storage**: Local + S3
- **WAF**: Caddy + Coraza
- **Email**: Swoosh (SMTP + Resend)
- **License**: AGPL v3

## Project Structure

```
hybridsocial/
  backend/          # Elixir/Phoenix API + Federation
  frontend/         # SvelteKit web app
  mobile/           # Flutter app
  docs/             # Specifications and documentation
  docker/           # Docker configs per service
  docker-compose.yml
```

## Commands

```bash
# Backend
cd backend && mix deps.get          # Install dependencies
cd backend && mix ecto.setup        # Create DB + migrate + seed
cd backend && mix test              # Run all tests
cd backend && mix test --only unit  # Run unit tests
cd backend && mix phx.server        # Start dev server

# Frontend
cd frontend && npm install          # Install dependencies
cd frontend && npm run dev          # Start dev server
cd frontend && npm run build        # Production build

# Docker (full stack)
docker compose up                   # Start all services
docker compose up -d                # Start detached
```

## Conventions

- All settings are database-backed, configurable at runtime via admin panel
- Environment variables only for infrastructure config (DB URL, S3 creds, secret key base)
- No hardcoded limits — everything configurable
- ActivityPub is a transport layer — internal model != AP representation
- Backend is authoritative for all permissions
- Soft deletes everywhere (deleted_at timestamps)
- UUID-based actor IDs for federation stability
- All tables have created_at / updated_at
- Tests for everything — unit, integration, federation conformance

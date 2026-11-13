# Changelog

HybridSocial uses calendar versioning: `YYYY.MM.N`, where `N` counts releases
within the month from 0. The running build's commit is shown alongside the
version (site footer, admin service panel, `/api/v1/instance/info`).

## 2026.11.0

First versioned release. Before this, every build reported the `mix new`
default, `0.1.0`.

### Federation
- Inbound deliveries from Mastodon servers running secure mode (authorized
  fetch), including mastodon.social, mastodon.online and kolektiva.social, are
  verified again: the key fetch is signed and cached, the instance actor
  (`/actor`) is routed and resolvable over WebFinger, including under former
  host names (#273, #274, #275, #276).
- Post object ids (`/posts/:id`, `/dm/:id`) are reachable by peers, so reply
  chains and quotes resolve (#271); browsers opening them are redirected to the
  post page (#280).
- RFC 9421 HTTP Message Signatures are verified on inbound requests (#281).
- Failed deliveries are retried on transient errors, never resurrecting
  deleted posts or undone actions (#279); no delivery rows are queued for peers
  whose circuit is open (#272).
- Image-only remote posts are kept (#269); remote ids and URLs longer than 255
  characters are stored (#268).

### Features
- Timed posts that delete themselves, tier-gated (#262).
- Trust levels: new accounts can't post links or DM strangers until established
  (#263). Group DMs respect blocks, DM preferences and an opt-in (#265).

### Media and privacy
- The media proxy shows an "Image not available" placeholder when the source
  refuses (#277) and serves media with its cache disabled (#270).

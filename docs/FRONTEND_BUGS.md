# Frontend Bug Tracker

Status: 2026-03-22
Backend: 970 tests, 164 files
Frontend: 104 files, builds clean

## Fixed

- [x] CORS — added cors_plug
- [x] Login redirect — wired auth store + setTokens
- [x] SSE streaming 406 — registered event-stream MIME type, separate :sse pipeline
- [x] SSE streaming 401 — auth plug reads access_token from query params
- [x] Post click 404 — created /post/[id] detail page
- [x] Boost/react wrong URLs — /api/v1/posts → /api/v1/statuses, /reaction → /react
- [x] React body param — {emoji} → {type: emoji}
- [x] List create — {title} → {name}
- [x] List display — list.title → list.name
- [x] List timeline URL — /lists/:id/timeline → /timelines/list/:id
- [x] List members URL — /lists/:id/members → /lists/:id/accounts
- [x] Group timeline URL — /groups/:id/timeline → /timelines/group/:id
- [x] Profile lookup — acct=@handle → handle=handle (strip @)
- [x] Profile statuses 404 — added /accounts/:id/statuses route + controller action
- [x] DM conversations crash — result.data → handle array response
- [x] DM messages crash — result.data → handle array response
- [x] DM participant names — backend now returns handle/display_name/avatar_url with participants
- [x] MessageBubble crash — null safety for media_attachments and sender
- [x] Groups crash — result.data → handle array response
- [x] Group members crash — backend now returns account data with members
- [x] Delete post — added confirmation dialog
- [x] PostCard media crash — media_attachments null safety
- [x] Tabs crash — optional chaining on tabs?.length
- [x] Explore search — statuses/posts field mapping, null defaults
- [x] Privacy settings — /preferences → /dm_preferences, field mapping
- [x] Notification preferences — /notifications/preferences → /notification_preferences
- [x] FeedList boosts — unwrap boost entries, show "User boosted" label
- [x] Trending API URL — /trends → /trends/tags

## Open / TODO

### Group Admin Features
- [ ] Group edit form (name, description, visibility, join_policy) — admin/owner only
- [ ] Delete group button with confirmation — owner only
- [ ] Remove member button — admin/owner
- [ ] Change member role — admin/owner
- [ ] Group settings page accessible from group detail header

### General UI Polish
- [ ] Post composer visibility selector doesn't work
- [ ] Profile edit doesn't save changes
- [ ] Search results don't navigate correctly
- [ ] Notification items don't navigate to content
- [ ] SSE reconnection on token refresh
- [ ] Mobile responsive testing
- [ ] RTL testing
- [ ] Dark mode (planned for later)
- [ ] Skeleton animations on more pages
- [ ] Error toasts for failed API calls
- [ ] Empty states with better illustrations

### Admin Panel
- [ ] Dashboard stats need real API data
- [ ] User management table
- [ ] Report management
- [ ] Content filters CRUD
- [ ] Federation dashboard
- [ ] Theme editor live preview
- [ ] Settings editor
- [ ] Backup management

### Backend API Gaps
- [ ] Many pages expect PaginatedResponse {data, next_cursor} but backend returns arrays
  → Need to standardize: either wrap all responses or fix all frontend pages
- [ ] /api/v1/preferences endpoint doesn't exist (privacy page)
- [ ] Group settings API (update screening, etc.) needs testing
- [ ] Post analytics endpoint
- [ ] Announcement endpoints

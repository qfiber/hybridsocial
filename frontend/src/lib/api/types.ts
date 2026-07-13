// HybridSocial API type definitions

export interface TierLimits {
  char_limit: number;
  markdown: 'none' | 'basic' | 'full' | 'full_embeds';
  video_resolution: number;
  video_duration: number;
  image_size_mb: number;
  video_size_mb: number;
  media_per_post: number;
  poll_options: number;
  edit_window: number;
  pinned_posts: number;
  profile_fields: number;
  scheduled_posts: boolean;
  custom_emoji: boolean;
  follows_limit: number;
  audio_allowed: boolean;
  audio_size_mb: number;
  audio_duration: number;
}

/**
 * User-facing handle helper. Prefers the `acct` field emitted by
 * the backend's identity serializer — that's already in webfinger
 * form (`user@domain` for remote, bare `user` for local). Falls
 * back to `handle` for older payloads that don't ship `acct` yet
 * so no call site needs to guard for undefined.
 */
export function displayAcct(identity: { handle?: string; acct?: string | null }): string {
  return identity.acct || identity.handle || '';
}

export interface Identity {
  id: string;
  type: 'user' | 'bot' | 'group' | 'page';
  handle: string;
  acct?: string;
  url?: string;
  domain?: string | null;
  display_name: string | null;
  bio: string | null;
  /** Server-rendered safe HTML for the bio. Remote bios go through
   *  HtmlSanitizeEx.basic_html; local bios are escaped + nl→<br>. */
  bio_html?: string | null;
  /** Custom emojis (from a remote actor's tag) referenced by
   *  `:shortcode:` in the display_name/bio. Empty/absent for locals. */
  emojis?: PostEmoji[];
  avatar_url: string | null;
  header_url: string | null;
  is_locked: boolean;
  is_bot: boolean;
  is_admin: boolean;
  discoverable?: boolean;
  allow_unfurl?: boolean;
  /** When true, follower/following counts are hidden from other viewers. */
  hide_follow_counts?: boolean;
  roles: string[];
  permissions: string[];
  two_factor_enabled: boolean;
  verification_tier?: string | null;
  is_verified?: boolean;
  limits?: TierLimits;
  /** May be null when the profile owner has opted to hide counts and
   *  the viewer isn't them. */
  followers_count: number | null;
  following_count: number | null;
  post_count: number;
  birthday?: string | null;
  location?: string | null;
  profile_fields?: { name: string; value: string }[];
  onboarded_at?: string | null;
  created_at: string;
}

export interface PostReaction {
  name: string;
  count: number;
  me: boolean;
}

export interface PostMention {
  acct: string;
  id?: string;
  url?: string;
}

export interface PostTag {
  name: string;
  url: string;
}

export interface PostEmoji {
  shortcode: string;
  url: string;
  static_url: string;
  // Local custom emojis carry an admin-set category for the picker
  // grouping. Federated emojis don't have a category — they come
  // from the post's `tag` Emoji entries, which only ship shortcode +
  // image URL — so the field is optional here.
  category?: string | null;
}

export interface LinkCard {
  url: string;
  title: string | null;
  description: string | null;
  image: string | null;
  provider_name: string | null;
}

export interface Post {
  id: string;
  type: string;
  uri: string;
  url: string;
  content: string;
  content_html: string | null;
  visibility: 'public' | 'followers' | 'group' | 'direct' | 'list';
  sensitive: boolean;
  spoiler_text: string | null;
  language: string | null;
  post_type: 'text' | 'media' | 'video_stream' | 'poll' | 'article';
  reply_count: number;
  boost_count: number;
  reaction_count: number;
  is_pinned: boolean;
  // Which container the pin actually belongs to. Lets the UI hide the
  // "Pinned" badge / Unpin entry on feeds outside that scope so a
  // group-pin doesn't read as a profile-pin when the same row shows
  // up on the parent profile timeline.
  pin_scope?: 'profile' | 'group' | 'page' | null;
  is_boosted: boolean;
  is_bookmarked: boolean;
  is_muted: boolean;
  current_user_reaction: string | null;
  // Admin-moderation flags. Present on admin-serialized posts and
  // when the viewer is staff; otherwise null. The regular post
  // serializer drops these since non-staff users don't need to know.
  hidden_at?: string | null;
  replies_locked_at?: string | null;
  // Denormalized pending-report count. Only included by the backend
  // for staff viewers; undefined for everyone else. Drives the
  // numeric badge on the admin moderation shield.
  open_report_count?: number;
  // Client-only flag set by the composer when it inserts an
  // optimistic post into a feed. Cleared when the server response
  // comes back via the post-replace event.
  pending?: boolean;
  created_at: string;
  edited_at: string | null;
  edit_expires_at: string | null;
  account: Identity;
  parent_id: string | null;
  root_id: string | null;
  /** Optional id of the parent's media attachment that this reply targets. */
  target_media_id?: string | null;
  /** 1-based position of `target_media_id` in the parent's gallery. */
  target_media_index?: number | null;
  /** Preview/thumbnail URL of the targeted image, for the reply indicator. */
  target_media_preview_url?: string | null;
  /**
   * Per-image reply counts keyed by media id. Only populated for posts that
   * own media attachments. `{}` for text-only or replies.
   */
  media_reply_counts?: Record<string, number>;
  /**
   * Per-image reaction counts keyed by media id. Mirrors
   * `media_reply_counts`. Drives the Instagram-style heart in the
   * lightbox.
   */
  media_reaction_counts?: Record<string, number>;
  in_reply_to_account_id: string | null;
  quote: Post | null;
  card: LinkCard | null;
  mentions: PostMention[];
  tags: PostTag[];
  emojis: PostEmoji[];
  reactions: PostReaction[];
  poll: Poll | null;
  media_attachments: MediaAttachment[];
  /**
   * When the post is anchored to a group, a small summary so the UI
   * can show the group chip + drive scope-aware behavior (e.g. the
   * pin action treating the post as a group pin instead of a profile
   * pin). Null when not in a group.
   */
  group?: { id: string; name: string; avatar_url?: string | null; visibility?: string } | null;
  /**
   * Like `group`, but for organization pages. The `id` is the page's
   * Identity row id; pages don't have a separate Page schema.
   */
  page?: { id: string; name: string; avatar_url?: string | null } | null;
  tombstone?: { reason: string };
}

export interface PostDraft {
  id: string;
  content: string | null;
  spoiler_text: string | null;
  sensitive: boolean;
  visibility: Post['visibility'];
  media_ids: string[];
  parent_id: string | null;
  quote_id: string | null;
  /** Group anchor — when set, publishing posts to this group. */
  group_id: string | null;
  /** Page anchor — when set, publishing posts to this page. */
  page_id: string | null;
  /** Group summary for displaying the "Posting to <group>" chip. */
  group?: { id: string; name: string; avatar_url?: string | null; visibility?: string } | null;
  /** Page summary for the "Posting to <page>" chip. */
  page?: { id: string; name: string; avatar_url?: string | null } | null;
  scheduled_at: string | null;
  poll_options: string[] | null;
  poll_multiple: boolean;
  poll_expires_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface BoostEntry {
  id: string;
  type: 'boost';
  created_at: string;
  account: Identity;
  post: Post;
}

export type FeedEntry = Post | BoostEntry;

export interface Poll {
  id: string;
  expires_at: string | null;
  expired: boolean;
  multiple: boolean;
  votes_count: number;
  voters_count: number;
  voted: boolean;
  own_votes: number[];
  options: PollOption[];
}

export interface PollOption {
  title: string;
  votes_count: number;
}

export interface MediaAttachment {
  id: string;
  type: 'image' | 'video' | 'audio' | 'gifv' | 'unknown';
  url: string;
  preview_url: string | null;
  remote_url: string | null;
  description: string | null;
  blurhash: string | null;
  meta: Record<string, unknown> | null;
}

export interface Notification {
  id: string;
  type:
    | 'mention'
    | 'reply'
    | 'quote'
    | 'boost'
    | 'favourite'
    | 'reaction'
    | 'follow'
    | 'follow_request'
    | 'poll'
    | 'poll_ended'
    | 'update'
    | 'group_invite'
    | 'group_application'
    | 'page_invite'
    | 'report'
    | 'admin';
  created_at: string;
  read: boolean;
  account: Identity;
  post: Post | null;
  // Set for post-related notification types when the post object isn't
  // eagerly joined — UI can follow target_id + target_type to link.
  target_id?: string | null;
  target_type?: 'post' | 'group' | 'page' | null;
  // For type === 'reaction': the actor's current reaction emoji code
  // (one of the canonical 7 like/love/wow/care/angry/sad/lol, or a
  // premium shortcode). Null if the actor since cleared their react.
  reaction_type?: string | null;
}

export interface Conversation {
  id: string;
  type: 'direct' | 'group_dm';
  accepted: boolean;
  is_local: boolean;
  // Three-state encryption indicator. "at_rest" = local, encrypted in our
  // DB, server can decrypt. "federated" = remote participants, plaintext
  // seen by their server. "e2ee" = reserved for future end-to-end.
  encryption_status: 'at_rest' | 'federated' | 'e2ee';
  /** @deprecated use encryption_status */
  is_encrypted: boolean;
  created_by_id: string | null;
  unread_count: number;
  last_message: Message | null;
  participants: ConversationParticipant[];
  created_at: string;
  updated_at: string;
}

// The backend ships conversation participants as the join-row, not the
// raw identity — so `id` is the conversation_participant uuid (unique
// per conversation) and the viewer's actual account is on
// `identity_id`. Code that needs to "filter out me" must compare the
// auth store's user id against `identity_id`, not `id`.
export interface ConversationParticipant {
  id: string;
  identity_id: string;
  handle: string | null;
  acct: string | null;
  display_name: string | null;
  avatar_url: string | null;
  joined_at: string | null;
  notifications_enabled: boolean;
  left_at: string | null;
}

export interface MessageReaction {
  emoji: string;
  count: number;
  accounts: { id: string; handle: string; display_name: string | null }[];
}

export interface Message {
  id: string;
  conversation_id: string;
  content: string;
  content_html: string | null;
  content_type: string;
  sender: Identity;
  media_attachments: MediaAttachment[];
  reply_to_id: string | null;
  reactions: MessageReaction[];
  created_at: string;
  edited_at: string | null;
  read_at: string | null;
  // Lowest delivery state across recipients. Server only populates this
  // on messages the current viewer sent — never on incoming ones — so
  // recipient bubbles never accidentally display ticks for someone
  // else's message.
  delivery_status?: 'sent' | 'delivered' | 'read' | null;
  pending?: boolean;
}

export interface Group {
  id: string;
  name: string;
  description: string | null;
  avatar_url: string | null;
  header_url: string | null;
  visibility: 'public' | 'private' | 'secret';
  // federation_mode is locked at creation — see backend Group schema.
  federation_mode: 'local_only' | 'public_federated';
  member_count: number;
  is_member: boolean;
  role: 'owner' | 'admin' | 'moderator' | 'member' | null;
  created_at: string;
  // Federated actor identity backing this group. Exposed so instance
  // admins/mods can target the underlying identity with the same
  // moderation tools used for users (silence, suspend, etc.).
  identity_id?: string | null;
  identity?: {
    id: string;
    handle: string;
    display_name: string | null;
    avatar_url: string | null;
  } | null;
}

export interface Relationship {
  id: string;
  following: boolean;
  followed_by: boolean;
  blocking: boolean;
  blocked_by: boolean;
  muting: boolean;
  muting_notifications: boolean;
  requested: boolean;
  domain_blocking: boolean;
  note: string | null;
}

export interface InstanceInfo {
  title: string;
  description: string;
  version: string;
  registrations_open: boolean;
  max_post_length: number;
  max_media_attachments: number;
  supported_mime_types: string[];
  contact_email: string | null;
  rules: InstanceRule[];
  stats: InstanceStats;
  theme: ThemeConfig | null;
  analytics?: unknown;
}

export interface InstanceRule {
  id: string;
  text: string;
}

export interface InstanceStats {
  user_count: number;
  post_count: number;
  domain_count: number;
}

export interface ThemeConfig {
  // Instance dark-mode policy. 'auto' follows the visitor's OS (default).
  // Dark is derived from the light theme (hybrid model); any dark_<key>
  // below overrides the derived/ramped value for that token.
  mode?: 'light' | 'dark' | 'auto';
  // Optional per-token dark overrides, e.g. dark_color_primary,
  // dark_color_bg, dark_color_surface, dark_color_text …
  [key: `dark_${string}`]: string | undefined;
  color_primary?: string;
  color_primary_hover?: string;
  color_primary_soft?: string;
  color_primary_contrast?: string;
  color_secondary?: string;
  color_accent?: string;
  color_success?: string;
  color_warning?: string;
  color_danger?: string;
  color_info?: string;
  color_bg?: string;
  // Lower-center radial wash applied to body. Admin-editable from the
  // theme page. Omitting means the CSS default (#f4f1fd) applies.
  color_bg_wash?: string;
  color_surface?: string;
  color_border?: string;
  color_text?: string;
  color_text_secondary?: string;
  color_text_link?: string;
  gradient_start?: string;
  gradient_end?: string;
  gradient_direction?: string;
  border_radius?: 'sharp' | 'rounded' | 'pill';
  density?: 'compact' | 'comfortable' | 'spacious';
  font_family?: string;
  logo_url?: string;
  favicon_url?: string;
}

export interface TrendingTag {
  name: string;
  url: string;
  history: { day: string; uses: number; accounts: number }[];
}

export interface SearchResults {
  accounts: Identity[];
  posts: Post[];
  hashtags: TrendingTag[];
}

export interface AuthTokens {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: string;
  identity_id?: string;
}

export interface TwoFactorSetup {
  secret: string;
  qr_code_url: string;
  backup_codes: string[];
  uri?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  next_cursor: string | null;
  prev_cursor: string | null;
}

export interface ApiErrorBody {
  error: string;
  error_description?: string;
  message?: string;
  details?: Record<string, string[]>;
}

export interface UserPreferences {
  feed_algorithm: 'chronological' | 'algorithmic';
  compact_mode: boolean;
  sidebar_position: 'left' | 'right';
  auto_play_media: boolean;
  default_visibility: Post['visibility'];
  default_language: string | null;
  comment_style: 'threaded' | 'flat';
  /** User's theme choice. `null` = follow the instance (admin) default. */
  theme_mode: 'auto' | 'light' | 'dark' | null;
}

export interface NotificationPreferences {
  mentions: boolean;
  boosts: boolean;
  favourites: boolean;
  follows: boolean;
  polls: boolean;
  group_invites: boolean;
}

// Admin types

export interface AdminUser {
  id: string;
  handle: string;
  email: string | null;
  display_name: string | null;
  bio: string | null;
  avatar_url: string | null;
  header_url: string | null;
  is_admin: boolean;
  is_bot: boolean;
  is_locked: boolean;
  is_local: boolean;
  domain: string | null;
  parent_identity_id: string | null;
  is_suspended: boolean;
  is_silenced: boolean;
  is_shadow_banned: boolean;
  force_sensitive: boolean;
  trust_level: number;
  post_count: number;
  followers_count: number;
  created_at: string;
  last_active_at: string | null;
  two_factor_enabled: boolean;
  email_confirmed?: boolean;
  confirmed_at?: string | null;
  verification_tier?: string | null;
}

export interface AdminReport {
  id: string;
  status: 'pending' | 'resolved' | 'dismissed';
  category: string;
  comment: string;
  created_at: string;
  updated_at: string;
  reporter: Identity;
  target_account: Identity;
  target_post: Post | null;
  assigned_to: Identity | null;
}

export interface ContentFilter {
  id: string;
  type: 'keyword' | 'regex' | 'domain';
  pattern: string;
  action: 'warn' | 'hide' | 'reject';
  replacement: string | null;
  scope: 'all' | 'local' | 'remote';
  created_at: string;
}

export interface BannedDomain {
  id: string;
  domain: string;
  reason: string | null;
  created_at: string;
}

export interface IpBlock {
  id: string;
  ip_address: string;
  subnet_mask: string | null;
  reason: string | null;
  expires_at: string | null;
  created_by: string | null;
  created_at: string;
}

export interface KnownInstance {
  id: string;
  domain: string;
  software: string | null;
  software_version: string | null;
  user_count: number;
  post_count: number;
  last_activity_at: string | null;
  first_seen_at: string;
  status: 'up' | 'down' | 'unknown';
}

export interface FederationPolicy {
  id: string;
  domain: string;
  policy: 'allow' | 'silence' | 'suspend' | 'force_nsfw' | 'block_media';
  reason: string | null;
  created_at: string;
  updated_at: string;
}

export interface Webhook {
  id: string;
  url: string;
  events: string[];
  secret: string | null;
  enabled: boolean;
  created_at: string;
  updated_at: string;
}

export interface Appeal {
  id: string;
  user: Identity;
  action_type: string;
  reason: string;
  response: string | null;
  status: 'pending' | 'approved' | 'rejected';
  submitted_at: string;
  resolved_at: string | null;
  resolved_by: Identity | null;
}

export interface ModerationNote {
  id: string;
  account_id: string;
  content: string;
  author: Identity;
  created_at: string;
}

export interface ModerationQueueItem {
  id: string;
  type: string;
  content_preview: string;
  source: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  status: 'pending' | 'approved' | 'rejected' | 'escalated';
  reason: string | null;
  created_at: string;
}

export interface ModerationQueueStats {
  pending: number;
  approved: number;
  rejected: number;
  escalated: number;
}

export interface InviteCode {
  id: string;
  code: string;
  uses: number;
  max_uses: number | null;
  expires_at: string | null;
  created_by: Identity;
  status: 'active' | 'expired' | 'disabled';
  created_at: string;
}

export interface EmailDomainBan {
  id: string;
  domain: string;
  reason: string | null;
  created_at: string;
}

export interface MediaHashBan {
  id: string;
  hash: string;
  hash_type: 'md5' | 'sha256' | 'phash';
  description: string | null;
  created_at: string;
}

export interface InstancePurgePreview {
  domain: string;
  users_count: number;
  posts_count: number;
  media_count: number;
}

export interface DeliveryQueueStats {
  pending: number;
  failed: number;
  retrying: number;
}

export interface AdminSetting {
  key: string;
  value: string;
  type: 'string' | 'integer' | 'boolean' | 'text' | 'json';
  category: string;
  description: string;
}

export interface ServiceHealth {
  status: 'up' | 'down' | 'degraded' | 'not_configured';
  backend?: string;
  version?: string;
  error?: string;
  uptime_seconds?: number;
  memory?: string;
  memory_peak?: string;
  total_keys?: number;
  connected_clients?: number;
  keyspace?: { db: string; keys: string; expires: string }[];
  cluster_name?: string;
  cluster_health?: string;
  node_count?: number;
  active_shards?: number;
  indices?: { name: string; health: string; docs_count: string; store_size: string; status: string }[];
  note?: string;
  integration?: string;
  connections?: number;
  total_messages?: number;
  jetstream_enabled?: boolean;
  js_streams?: number;
  js_consumers?: number;
}

export interface AdminDashboardStats {
  total_users: number;
  total_posts: number;
  known_instances: number;
  open_reports: number;
  pending_verifications: number;
  services: {
    valkey: ServiceHealth;
    opensearch: ServiceHealth;
    nats: ServiceHealth;
    database: ServiceHealth;
  };
}

export interface Backup {
  id: string;
  status: 'pending' | 'in_progress' | 'completed' | 'failed';
  size?: number | null;
  file_size?: number | null;
  file_path?: string | null;
  created_at: string;
  completed_at: string | null;
  started_at?: string | null;
  type?: string;
  initiated_by?: string | null;
  download_url?: string | null;
}

export interface AuditActor {
  id: string;
  handle: string;
  display_name: string | null;
  avatar_url: string | null;
}

// Backend-resolved, per-target_type view of the audited object.
// `label` is always present and safe to render verbatim; the extra
// fields (handle, excerpt, domain, code, …) are optional depending on
// target_type and are used for the detail modal.
export interface AuditTarget {
  label: string;
  deleted?: boolean;
  handle?: string;
  display_name?: string | null;
  excerpt?: string;
  author_handle?: string;
  reporter_handle?: string;
  reported_handle?: string;
  category?: string;
  status?: string;
  key?: string;
  domain?: string;
  inbox_url?: string;
  url?: string;
  code?: string;
  pattern?: string;
  action?: string;
  ip_address?: string;
  reason?: string;
  hash?: string;
  title?: string;
  action_type?: string;
  identity_handle?: string;
}

export interface AuditLogEntry {
  id: string;
  actor: AuditActor | null;
  action: string;
  target_type: string | null;
  target_id: string | null;
  target: AuditTarget | null;
  details: Record<string, unknown> | null;
  ip_address: string | null;
  created_at: string;
}

export interface Relay {
  id: string;
  inbox_url: string;
  actor_url: string | null;
  style: 'mastodon' | 'pleroma';
  status: 'pending' | 'accepted' | 'rejected' | 'failed';
  last_error: string | null;
  created_at: string;
}

export interface Announcement {
  id: string;
  content: string;
  starts_at: string | null;
  ends_at: string | null;
  published: boolean;
  created_at: string;
  updated_at: string;
}

export interface EmailConfig {
  provider: string;
  from_address: string;
  smtp_host: string | null;
  smtp_port: number | null;
  smtp_username: string | null;
  smtp_ssl: boolean;
  // True when the transport is pinned by the server environment
  // (RESEND_API_KEY / SMTP_* in .env). Provider + connection settings
  // are then read-only in the admin panel.
  env_override?: boolean;
  env_provider?: string | null;
}

export interface AdminRole {
  id: string;
  name: string;
  description: string | null;
  is_system: boolean;
  permissions: AdminPermission[];
  created_at: string;
}

export interface AdminPermission {
  id: string;
  name: string;
  description: string | null;
  category: string;
}

export interface PermissionCategory {
  category: string;
  permissions: AdminPermission[];
}

export interface AdminThemeConfig {
  color_primary: string;
  color_primary_hover: string;
  color_primary_soft: string;
  color_primary_contrast: string;
  color_secondary: string;
  color_accent: string;
  color_success: string;
  color_warning: string;
  color_danger: string;
  color_info: string;
  color_bg: string;
  color_bg_wash: string;
  color_surface: string;
  color_border: string;
  color_text: string;
  color_text_secondary: string;
  color_text_link: string;
  gradient_start: string;
  gradient_end: string;
  gradient_direction: string;
  border_radius: 'sharp' | 'rounded' | 'pill';
  density: 'compact' | 'comfortable' | 'spacious';
  font_family: string;
  instance_name: string;
  instance_description: string;
  logo_url: string | null;
  favicon_url: string | null;
  og_image_url: string | null;
  // Dark-mode policy + optional dark logo (shown when the theme resolves
  // to dark; falls back to logo_url).
  mode?: 'light' | 'dark' | 'auto';
  dark_logo_url?: string | null;
  // Optional dark-palette overrides. When empty/absent, the value is derived
  // (brand colours lifted from the light palette, surfaces/text from the
  // built-in dark ramp). Set one to pin a specific dark-mode colour.
  dark_color_primary?: string;
  dark_color_primary_hover?: string;
  dark_color_primary_soft?: string;
  dark_color_primary_contrast?: string;
  dark_color_secondary?: string;
  dark_color_accent?: string;
  dark_color_success?: string;
  dark_color_warning?: string;
  dark_color_danger?: string;
  dark_color_info?: string;
  dark_color_bg?: string;
  dark_color_bg_wash?: string;
  dark_color_surface?: string;
  dark_color_border?: string;
  dark_color_text?: string;
  dark_color_text_secondary?: string;
  dark_color_text_link?: string;
}

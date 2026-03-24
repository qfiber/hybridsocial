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
}

export interface Identity {
  id: string;
  type: 'user' | 'organization';
  handle: string;
  display_name: string | null;
  bio: string | null;
  avatar_url: string | null;
  header_url: string | null;
  is_locked: boolean;
  is_bot: boolean;
  is_admin: boolean;
  roles: string[];
  permissions: string[];
  two_factor_enabled: boolean;
  verification_tier?: string;
  limits?: TierLimits;
  followers_count: number;
  following_count: number;
  post_count: number;
  created_at: string;
}

export interface Post {
  id: string;
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
  is_boosted: boolean;
  is_bookmarked: boolean;
  current_user_reaction: string | null;
  created_at: string;
  edited_at: string | null;
  account: Identity;
  parent_id: string | null;
  quote: Post | null;
  poll: Poll | null;
  media_attachments: MediaAttachment[];
}

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
  type: 'mention' | 'boost' | 'favourite' | 'reaction' | 'follow' | 'follow_request' | 'poll' | 'update' | 'group_invite';
  created_at: string;
  read: boolean;
  account: Identity;
  post: Post | null;
}

export interface Conversation {
  id: string;
  unread_count: number;
  last_message: Message | null;
  participants: Identity[];
  created_at: string;
  updated_at: string;
}

export interface Message {
  id: string;
  conversation_id: string;
  content: string;
  content_html: string | null;
  sender: Identity;
  media_attachments: MediaAttachment[];
  created_at: string;
  edited_at: string | null;
  read_at: string | null;
}

export interface Group {
  id: string;
  name: string;
  description: string | null;
  avatar_url: string | null;
  header_url: string | null;
  visibility: 'public' | 'private' | 'secret';
  member_count: number;
  is_member: boolean;
  role: 'owner' | 'admin' | 'moderator' | 'member' | null;
  created_at: string;
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
  color_primary?: string;
  color_primary_hover?: string;
  color_primary_soft?: string;
  color_secondary?: string;
  color_accent?: string;
  gradient_start?: string;
  gradient_end?: string;
  gradient_direction?: string;
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
}

export interface TwoFactorSetup {
  secret: string;
  qr_code_url: string;
  backup_codes: string[];
}

export interface PaginatedResponse<T> {
  data: T[];
  next_cursor: string | null;
  prev_cursor: string | null;
}

export interface ApiErrorBody {
  error: string;
  error_description?: string;
  details?: Record<string, string[]>;
}

export interface UserPreferences {
  feed_algorithm: 'chronological' | 'algorithmic';
  compact_mode: boolean;
  sidebar_position: 'left' | 'right';
  auto_play_media: boolean;
  default_visibility: Post['visibility'];
  default_language: string | null;
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
  email: string;
  display_name: string | null;
  is_admin: boolean;
  is_bot: boolean;
  is_locked: boolean;
  status: 'active' | 'suspended' | 'pending';
  post_count: number;
  followers_count: number;
  created_at: string;
  last_active_at: string | null;
  two_factor_enabled: boolean;
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
  ip: string;
  severity: 'sign_up_block' | 'sign_up_requires_approval' | 'no_access';
  comment: string | null;
  expires_at: string | null;
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
  policy: 'allow' | 'silence' | 'suspend';
  reason: string | null;
  created_at: string;
  updated_at: string;
}

export interface DeliveryQueueStats {
  pending: number;
  failed: number;
  retrying: number;
}

export interface AdminSetting {
  key: string;
  value: string;
  type: 'string' | 'integer' | 'boolean' | 'text';
  category: string;
  description: string;
}

export interface ServiceHealth {
  status: 'up' | 'down' | 'degraded';
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
  size: number | null;
  created_at: string;
  completed_at: string | null;
  download_url: string | null;
}

export interface AuditLogEntry {
  id: string;
  actor: Identity;
  action: string;
  target_type: string | null;
  target_id: string | null;
  details: Record<string, unknown> | null;
  created_at: string;
}

export interface Relay {
  id: string;
  inbox_url: string;
  status: 'pending' | 'accepted' | 'rejected';
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
}

import { api } from './client.js';
import type {
  Post,
  AdminUser,
  AdminReport,
  ContentFilter,
  BannedDomain,
  IpBlock,
  KnownInstance,
  FederationPolicy,
  DeliveryQueueStats,
  AdminSetting,
  AdminDashboardStats,
  Backup,
  AuditLogEntry,
  Relay,
  Announcement,
  EmailConfig,
  TranslationConfig,
  AdminThemeConfig,
  PaginatedResponse,
  Webhook,
  Appeal,
  ModerationNote,
  ModerationQueueItem,
  ModerationQueueStats,
  InviteCode,
  EmailDomainBan,
  MediaHashBan,
  InstancePurgePreview,
  AdminRole
} from './types.js';

// Role summary attached to an identity. Each `id` is the identity_role
// row id (not the role id) — that's what DELETE .../roles/:id expects.
export interface UserRoleAssignment {
  id: string;
  role_id: string;
  role_name: string;
  role_description: string | null;
  is_system: boolean;
  granted_at: string;
  expires_at: string | null;
}

// Dashboard
export function getDashboardStats(): Promise<AdminDashboardStats> {
  return api.get('/api/v1/admin/dashboard');
}

export function getRecentReports(): Promise<AdminReport[]> {
  return api.get('/api/v1/admin/reports', { limit: '5' });
}

// Users
export function getAdminUsers(params?: Record<string, string>): Promise<PaginatedResponse<AdminUser>> {
  return api.get('/api/v1/admin/users', params);
}

export function getAdminUser(id: string): Promise<AdminUser> {
  return api.get(`/api/v1/admin/users/${id}`);
}

/**
 * An account's own content for the admin panel's Content tabs.
 * `type` is 'posts' (top-level only), 'replies' or 'media'.
 * Privately-addressed statuses (direct/list) are never returned — reading those
 * is a separate policy decision, not part of "show me what this account posted".
 */
export function getAdminUserStatuses(
  id: string,
  params?: { type?: string; max_id?: string; limit?: string },
): Promise<Post[]> {
  return api.get(`/api/v1/admin/users/${id}/statuses`, params as Record<string, string>);
}

export interface CreateAdminUserPayload {
  handle: string;
  email: string;
  password: string;
  display_name?: string;
  bio?: string;
  auto_confirm?: boolean;
  // Role *names* (e.g. "admin", "moderator") — backend resolves to ids.
  roles?: string[];
}

export function createAdminUser(
  payload: CreateAdminUserPayload
): Promise<{ data: AdminUser; assigned_roles: string[] }> {
  return api.post('/api/v1/admin/users', payload);
}

export function suspendUser(id: string): Promise<void> {
  return api.post(`/api/v1/admin/users/${id}/suspend`);
}

export function unsuspendUser(id: string): Promise<void> {
  return api.post(`/api/v1/admin/users/${id}/unsuspend`);
}

export interface DeleteUserSummary {
  identities: number;
  posts_deleted: number;
  media_deleted: number;
  conversations_dropped: number;
}

// Permanent: purges posts/replies/media (incl. storage blobs), drops DMs
// where the other party is also deleted, and soft-deletes the account so
// remaining DMs render as "Deleted User".
export function deleteUser(id: string): Promise<{ status: string; data: DeleteUserSummary }> {
  return api.delete(`/api/v1/admin/users/${id}`);
}

export function warnUser(id: string, message: string): Promise<void> {
  return api.post(`/api/v1/admin/users/${id}/warn`, { message });
}

export function resetUserPassword(id: string): Promise<{ password: string }> {
  return api.post(`/api/v1/admin/users/${id}/reset_password`);
}

export function sendUserPasswordResetEmail(id: string): Promise<{ status: string }> {
  return api.post(`/api/v1/admin/users/${id}/send_password_reset_email`);
}

export function disableUserTwoFactor(id: string): Promise<{ status: string }> {
  return api.delete(`/api/v1/admin/users/${id}/otp`);
}

export function changeUserEmail(id: string, email: string): Promise<{ status: string; email: string }> {
  return api.put(`/api/v1/admin/users/${id}/email`, { email });
}

export function confirmUserEmail(id: string): Promise<{ status: string; confirmed_at?: string }> {
  return api.post(`/api/v1/admin/users/${id}/confirm_email`);
}

export function changeUserTier(id: string, tier: string): Promise<{ data: AdminUser }> {
  return api.put(`/api/v1/admin/users/${id}/tier`, { tier });
}

// Admin override for the per-tier rule that blocks verified accounts
// from editing their own display_name. Goes through admin_update_changeset
// on the backend, which skips that rule.
export function editUserProfile(
  id: string,
  attrs: {
    display_name?: string | null;
    bio?: string | null;
    // Pass null to clear the user's avatar / header (hero) image.
    avatar_url?: string | null;
    header_url?: string | null;
  },
): Promise<{ data: AdminUser }> {
  return api.put(`/api/v1/admin/users/${id}/profile`, attrs);
}

// Reports
export function getReports(params?: Record<string, string>): Promise<PaginatedResponse<AdminReport>> {
  return api.get('/api/v1/admin/reports', params);
}

export function resolveReport(id: string): Promise<AdminReport> {
  return api.post(`/api/v1/admin/reports/${id}/resolve`);
}

export function dismissReport(id: string): Promise<AdminReport> {
  return api.post(`/api/v1/admin/reports/${id}/dismiss`);
}

export function assignReport(id: string, assigneeId: string): Promise<AdminReport> {
  return api.post(`/api/v1/admin/reports/${id}/assign`, { assignee_id: assigneeId });
}

// Content Filters
export function getContentFilters(): Promise<ContentFilter[]> {
  return api.get('/api/v1/admin/content_filters');
}

export function createContentFilter(filter: Omit<ContentFilter, 'id' | 'created_at'>): Promise<ContentFilter> {
  return api.post('/api/v1/admin/content_filters', filter);
}

export function deleteContentFilter(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/content_filters/${id}`);
}

// Banned Domains
export function getBannedDomains(): Promise<BannedDomain[]> {
  return api.get('/api/v1/admin/banned_domains');
}

export function banDomain(domain: string, reason?: string): Promise<BannedDomain> {
  return api.post('/api/v1/admin/banned_domains', { domain, reason });
}

export function unbanDomain(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/banned_domains/${id}`);
}

// IP Blocks
export function getIpBlocks(): Promise<IpBlock[]> {
  // Backend calls the table "ip_bans"; the frontend keeps the
  // "ip_blocks"/"IpBlock" vocabulary on the UI since that's what
  // admins expect to see. Path-level rename only.
  return api.get<{ data: IpBlock[] }>('/api/v1/admin/ip_bans').then((r) => r.data);
}

export function createIpBlock(block: Omit<IpBlock, 'id' | 'created_at' | 'created_by'>): Promise<IpBlock> {
  return api.post<{ data: IpBlock }>('/api/v1/admin/ip_bans', block).then((r) => r.data);
}

export function deleteIpBlock(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/ip_bans/${id}`);
}

// Federation
export function getKnownInstances(): Promise<{ data: KnownInstance[] }> {
  return api.get('/api/v1/admin/known_instances');
}

export function getFederationPolicies(): Promise<FederationPolicy[]> {
  return api.get<{ data: FederationPolicy[] }>('/api/v1/admin/instance_policies').then(r => r.data || []);
}

export function createFederationPolicy(policy: Omit<FederationPolicy, 'id' | 'created_at' | 'updated_at'>): Promise<FederationPolicy> {
  return api.post('/api/v1/admin/instance_policies', policy);
}

export function updateFederationPolicy(id: string, policy: Partial<FederationPolicy>): Promise<FederationPolicy> {
  return api.put(`/api/v1/admin/instance_policies/${id}`, policy);
}

export function deleteFederationPolicy(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/instance_policies/${id}`);
}

export function getDeliveryQueueStats(): Promise<DeliveryQueueStats> {
  return api.get('/api/v1/admin/queue_stats');
}

export function retryDeliveryQueue(): Promise<void> {
  return api.post('/api/v1/admin/queue_stats');
}

// Settings
export function getAdminSettings(): Promise<AdminSetting[]> {
  return api.get('/api/v1/admin/settings');
}

// value may be a string, number, or boolean — the backend stores it as-is
// (no coercion), and some settings are read back as typed (e.g. pow_enabled
// is compared `== true`, pow_difficulty is used as an integer), so callers
// must send the right JSON type, not a stringified one.
export function updateAdminSettings(
  settings: { key: string; value: string | number | boolean }[],
): Promise<AdminSetting[]> {
  return api.put('/api/v1/admin/settings', { settings });
}

// Theme
export function getAdminTheme(): Promise<AdminThemeConfig> {
  return api.get('/api/v1/admin/theme');
}

// Accepts a partial: the backend only writes the keys present in the
// payload, so callers can omit fields they don't own (e.g. the Theme
// page no longer sends instance_name/description — those live on
// Instance › General now).
export function saveAdminTheme(theme: Partial<AdminThemeConfig>): Promise<AdminThemeConfig> {
  return api.put('/api/v1/admin/theme', theme);
}

export function uploadLogo(file: File, variant?: 'light' | 'dark'): Promise<{ url: string }> {
  return api.upload('/api/v1/admin/theme/logo', file, variant ? { variant } : undefined);
}

export function uploadOgImage(file: File): Promise<{ url: string }> {
  return api.upload('/api/v1/admin/theme/og_image', file);
}

export function uploadFavicon(file: File): Promise<{ url: string }> {
  return api.upload('/api/v1/admin/theme/favicon', file);
}

// Backups
export function getBackups(): Promise<Backup[]> {
  return api.get<any>('/api/v1/admin/backups').then(r => Array.isArray(r) ? r : r.data || []);
}

export function createBackup(passphrase?: string): Promise<Backup> {
  return api.post<any>('/api/v1/admin/backup', { passphrase }).then(r => r.data || r);
}

// Backup files are binary — the api client helper always does JSON,
// so just return the endpoint URL and let the browser handle the
// download with credentials on the same origin.
export function backupDownloadUrl(id: string): string {
  const base = import.meta.env.VITE_API_URL || '';
  return `${base}/api/v1/admin/backups/${id}/download`;
}

export function restoreBackup(id: string, passphrase: string, confirmation: string): Promise<{ status: string; message: string }> {
  return api.post(`/api/v1/admin/backups/${id}/restore`, { passphrase, confirmation });
}

export function deleteBackup(id: string): Promise<{ status: string }> {
  return api.delete(`/api/v1/admin/backups/${id}`);
}

// Audit Log
export function getAuditLog(params?: Record<string, string>): Promise<PaginatedResponse<AuditLogEntry>> {
  return api.get('/api/v1/admin/audit_log', params);
}

// Relays
export function getRelays(): Promise<Relay[]> {
  return api.get<{ data: Relay[] }>('/api/v1/admin/relays').then(r => r.data || []);
}

export function addRelay(inboxUrl: string): Promise<Relay> {
  return api.post<{ data: Relay }>('/api/v1/admin/relays', { inbox_url: inboxUrl }).then(r => r.data);
}

export function removeRelay(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/relays/${id}`);
}

// Announcements
export function getAnnouncements(): Promise<Announcement[]> {
  return api.get('/api/v1/admin/announcements');
}

export function createAnnouncement(announcement: { content: string; starts_at?: string; ends_at?: string }): Promise<Announcement> {
  return api.post('/api/v1/admin/announcements', announcement);
}

export function deleteAnnouncement(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/announcements/${id}`);
}

// Email
export function getEmailConfig(): Promise<EmailConfig> {
  return api.get('/api/v1/admin/email');
}

export function updateEmailConfig(config: Partial<EmailConfig>): Promise<EmailConfig> {
  return api.put('/api/v1/admin/email', config);
}

export function sendTestEmail(to: string): Promise<void> {
  return api.post('/api/v1/admin/email/test', { to });
}

// Post translation
export function getTranslationConfig(): Promise<TranslationConfig> {
  return api.get('/api/v1/admin/translation');
}

export function updateTranslationConfig(
  config: Partial<TranslationConfig>,
): Promise<TranslationConfig> {
  return api.put('/api/v1/admin/translation', config);
}

// Verifications
export interface VerificationRequest {
  id: string;
  type: string;
  status: string;
  metadata: Record<string, unknown>;
  rejection_reason: string | null;
  verified_at: string | null;
  created_at: string;
  account: {
    id: string;
    handle: string;
    display_name: string | null;
    avatar_url: string | null;
  } | null;
}

export function getVerifications(params?: Record<string, string>): Promise<VerificationRequest[]> {
  return api.get<{ data: VerificationRequest[] }>('/api/v1/admin/verifications', params).then((r) => r.data);
}

export function approveVerification(id: string): Promise<VerificationRequest> {
  return api.post<{ data: VerificationRequest }>(`/api/v1/admin/verifications/${id}/approve`).then((r) => r.data);
}

export function rejectVerification(id: string, reason?: string): Promise<VerificationRequest> {
  return api
    .post<{ data: VerificationRequest }>(`/api/v1/admin/verifications/${id}/reject`, reason ? { reason } : {})
    .then((r) => r.data);
}

// Site Pages (legal / about)
export interface SitePage {
  id: string;
  slug: string;
  title: string;
  body_markdown: string;
  body_html: string;
  published: boolean;
  last_edited_by: string | null;
  updated_at: string;
  created_at: string;
}

export function getSitePages(): Promise<SitePage[]> {
  return api.get<{ data: SitePage[] }>('/api/v1/admin/site_pages').then((r) => r.data);
}

export function getSitePage(id: string): Promise<SitePage> {
  return api.get<{ data: SitePage }>(`/api/v1/admin/site_pages/${id}`).then((r) => r.data);
}

export function updateSitePage(id: string, attrs: { title?: string; body_markdown?: string; published?: boolean }): Promise<SitePage> {
  return api.put<{ data: SitePage }>(`/api/v1/admin/site_pages/${id}`, attrs).then((r) => r.data);
}

export function seedSitePages(): Promise<SitePage[]> {
  return api.post<{ data: SitePage[] }>('/api/v1/admin/site_pages/seed').then((r) => r.data);
}

// Webhooks
export function getWebhooks(): Promise<{ data: Webhook[]; known_events: string[] }> {
  return api.get<any>('/api/v1/admin/webhooks').then(r => ({
    data: r.data || [],
    known_events: r.known_events || []
  }));
}

export function createWebhook(webhook: { url: string; events: string[]; secret?: string; enabled?: boolean }): Promise<Webhook> {
  return api.post<any>('/api/v1/admin/webhooks', webhook).then(r => r.data || r);
}

export function updateWebhook(id: string, webhook: Partial<{ url: string; events: string[]; secret: string; enabled: boolean }>): Promise<Webhook> {
  return api.put<any>(`/api/v1/admin/webhooks/${id}`, webhook).then(r => r.data || r);
}

export function deleteWebhook(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/webhooks/${id}`);
}

export interface WebhookDelivery {
  id: string;
  event: string;
  status: 'pending' | 'delivered' | 'failed';
  attempts: number;
  last_status_code: number | null;
  last_error: string | null;
  next_attempt_at: string;
  delivered_at: string | null;
  created_at: string;
}

export function getWebhookDeliveries(id: string): Promise<WebhookDelivery[]> {
  return api.get<{ data: WebhookDelivery[] }>(`/api/v1/admin/webhooks/${id}/deliveries`).then(r => r.data || []);
}

// Appeals
export function getAppeals(params?: Record<string, string>): Promise<Appeal[]> {
  return api.get<{ data: Appeal[] }>('/api/v1/admin/appeals', params).then(r => r.data || []);
}

export function approveAppeal(id: string, response?: string): Promise<Appeal> {
  return api.post<{ data: Appeal }>(`/api/v1/admin/appeals/${id}/approve`, { response }).then(r => r.data);
}

export function rejectAppeal(id: string, response?: string): Promise<Appeal> {
  return api.post<{ data: Appeal }>(`/api/v1/admin/appeals/${id}/reject`, { response }).then(r => r.data);
}

// Moderation Notes
export function getModerationNotes(accountId: string): Promise<ModerationNote[]> {
  return api.get<any>(`/api/v1/admin/users/${accountId}/notes`).then(r => r.data || r);
}

export function createModerationNote(accountId: string, content: string): Promise<ModerationNote> {
  return api.post<any>(`/api/v1/admin/users/${accountId}/notes`, { content }).then(r => r.data || r);
}

export function deleteModerationNote(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/notes/${id}`);
}

// Moderation Queue
export function getModerationQueue(params?: Record<string, string>): Promise<ModerationQueueItem[]> {
  return api.get<{ data: ModerationQueueItem[] }>('/api/v1/admin/moderation_queue', params).then(r => r.data || []);
}

export function getModerationQueueStats(): Promise<ModerationQueueStats> {
  return api.get<{ data: ModerationQueueStats }>('/api/v1/admin/moderation_queue/stats').then(r => r.data);
}

export function approveQueueItem(id: string): Promise<ModerationQueueItem> {
  return api.post<{ data: ModerationQueueItem }>(`/api/v1/admin/moderation_queue/${id}/approve`).then(r => r.data);
}

export function rejectQueueItem(id: string, reason?: string): Promise<ModerationQueueItem> {
  return api.post<{ data: ModerationQueueItem }>(`/api/v1/admin/moderation_queue/${id}/reject`, { reason }).then(r => r.data);
}

export function escalateQueueItem(id: string): Promise<ModerationQueueItem> {
  return api.post<{ data: ModerationQueueItem }>(`/api/v1/admin/moderation_queue/${id}/escalate`).then(r => r.data);
}

// Invite Codes
export function getInvites(): Promise<InviteCode[]> {
  return api.get<any>('/api/v1/admin/invites').then(r => r.data || r);
}

export function createInvite(params: { max_uses?: number; expires_at?: string }): Promise<InviteCode> {
  return api.post<any>('/api/v1/admin/invites', params).then(r => r.data || r);
}

export function deleteInvite(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/invites/${id}`);
}

// Email Domain Bans
export function getEmailDomainBans(): Promise<EmailDomainBan[]> {
  return api.get('/api/v1/admin/email_domain_bans');
}

export function createEmailDomainBan(domain: string, reason?: string): Promise<EmailDomainBan> {
  return api.post('/api/v1/admin/email_domain_bans', { domain, reason });
}

export function deleteEmailDomainBan(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/email_domain_bans/${id}`);
}

// Media Hash Bans
export function getMediaHashBans(): Promise<MediaHashBan[]> {
  return api.get('/api/v1/admin/media_hash_bans');
}

export function createMediaHashBan(params: { hash: string; hash_type: string; description?: string }): Promise<MediaHashBan> {
  return api.post('/api/v1/admin/media_hash_bans', params);
}

export function deleteMediaHashBan(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/media_hash_bans/${id}`);
}

export function banMediaFromPost(postId: string): Promise<void> {
  return api.post(`/api/v1/admin/media_hash_bans/from_post/${postId}`);
}

// Instance Purge
export function purgeInstancePreview(policyId: string): Promise<InstancePurgePreview> {
  return api.post(`/api/v1/admin/instance_policies/${policyId}/purge_preview`);
}

export function purgeInstanceContent(policyId: string): Promise<void> {
  return api.post(`/api/v1/admin/instance_policies/${policyId}/purge`);
}

// Admin Post Actions
export function adminGetPost(id: string): Promise<Record<string, unknown>> {
  return api.get(`/api/v1/admin/posts/${id}`);
}

export function adminDeletePost(id: string, reason?: string): Promise<void> {
  return api.delete(`/api/v1/admin/posts/${id}`, reason ? { reason } : undefined);
}

export function adminForceSensitive(id: string): Promise<void> {
  return api.post(`/api/v1/admin/posts/${id}/sensitive`);
}

export function adminRemoveSensitive(id: string): Promise<void> {
  return api.post(`/api/v1/admin/posts/${id}/unsensitive`);
}

export function adminHidePost(id: string): Promise<void> {
  return api.post(`/api/v1/admin/posts/${id}/hide`);
}

export function adminUnhidePost(id: string): Promise<void> {
  return api.post(`/api/v1/admin/posts/${id}/unhide`);
}

export function adminLockReplies(id: string): Promise<void> {
  return api.post(`/api/v1/admin/posts/${id}/lock_replies`);
}

export function adminUnlockReplies(id: string): Promise<void> {
  return api.post(`/api/v1/admin/posts/${id}/unlock_replies`);
}

export function adminRefetchPost(id: string): Promise<void> {
  return api.post(`/api/v1/admin/posts/${id}/refetch`);
}

// Account Actions
export function silenceUser(id: string, params?: { duration?: number; reason?: string }): Promise<AdminUser> {
  return api.post(`/api/v1/admin/users/${id}/silence`, params);
}

export function unsilenceUser(id: string): Promise<AdminUser> {
  return api.post(`/api/v1/admin/users/${id}/unsilence`);
}

export function shadowBanUser(id: string): Promise<AdminUser> {
  return api.post(`/api/v1/admin/users/${id}/shadow_ban`);
}

export function unshadowBanUser(id: string): Promise<AdminUser> {
  return api.post(`/api/v1/admin/users/${id}/unshadow_ban`);
}

export function forceSensitiveUser(id: string): Promise<AdminUser> {
  return api.post(`/api/v1/admin/users/${id}/force_sensitive`);
}

export function unforceSensitiveUser(id: string): Promise<AdminUser> {
  return api.post(`/api/v1/admin/users/${id}/unforce_sensitive`);
}

export function revokeAllSessions(id: string): Promise<void> {
  return api.post(`/api/v1/admin/users/${id}/revoke_sessions`);
}

export function setTrustLevel(id: string, level: number): Promise<AdminUser> {
  return api.post(`/api/v1/admin/users/${id}/trust_level`, { level });
}

// Roles — catalog + per-user assignments.
export function getRoles(): Promise<AdminRole[]> {
  return api.get<{ data: AdminRole[] }>('/api/v1/admin/roles').then((r) => r.data || []);
}

export function getUserRoles(userId: string): Promise<UserRoleAssignment[]> {
  return api
    .get<{ data: UserRoleAssignment[] }>(`/api/v1/admin/users/${userId}/roles`)
    .then((r) => r.data || []);
}

export function assignUserRole(
  userId: string,
  roleId: string,
  expiresAt?: string
): Promise<UserRoleAssignment> {
  const body: { role_id: string; expires_at?: string } = { role_id: roleId };
  if (expiresAt) body.expires_at = expiresAt;

  return api
    .post<{ data: UserRoleAssignment }>(`/api/v1/admin/users/${userId}/roles`, body)
    .then((r) => r.data);
}

// `identityRoleId` is the id of the assignment row (from getUserRoles),
// not the role's own id — the backend route's `:role_id` path param is
// a legacy name.
export function revokeUserRole(userId: string, identityRoleId: string): Promise<void> {
  return api.delete(`/api/v1/admin/users/${userId}/roles/${identityRoleId}`);
}

// ── Admin post detail ────────────────────────────────────────────────

export interface AdminPostDetail {
  id: string;
  content: string;
  content_html: string | null;
  post_type: string;
  visibility: string;
  sensitive: boolean;
  spoiler_text: string | null;
  language: string | null;
  identity_id: string | null;
  parent_id: string | null;
  root_id: string | null;
  quote_id: string | null;
  ap_id: string | null;
  reply_count: number;
  boost_count: number;
  reaction_count: number;
  is_pinned: boolean;
  published_at: string | null;
  edited_at: string | null;
  deleted_at: string | null;
  hidden_at: string | null;
  replies_locked_at: string | null;
  created_at: string;
  identity: { id: string; handle: string; display_name: string | null } | null;
  media: Array<{
    id: string;
    content_type: string;
    alt_text: string | null;
    storage_path: string | null;
    remote_url: string | null;
  }>;
  reports: Array<{
    id: string;
    category: string;
    comment: string | null;
    status: string;
    created_at: string;
    reporter: { id: string; handle: string; display_name: string | null } | null;
  }>;
  audit_log: Array<{
    id: string;
    action: string;
    details: Record<string, unknown> | null;
    created_at: string;
    actor: { id: string; handle: string; display_name: string | null } | null;
  }>;
  author_pending_reports: number;
}

export function getAdminPost(id: string): Promise<AdminPostDetail> {
  return api.get<{ data: AdminPostDetail }>(`/api/v1/admin/posts/${id}`).then((r) => r.data);
}

// ── Email templates ──────────────────────────────────────────────────

export interface EmailTemplate {
  key: string;
  name: string;
  description: string;
  variables: Record<string, string>;
  default_subject: string;
  default_html: string;
  subject: string;
  html_body: string;
  enabled: boolean;
  customized: boolean;
  updated_at: string | null;
}

export interface EmailTemplatePreview {
  subject: string;
  html: string;
  text: string;
}

export function getEmailTemplates(): Promise<EmailTemplate[]> {
  return api.get<{ data: EmailTemplate[] }>('/api/v1/admin/email_templates').then((r) => r.data || []);
}

export function updateEmailTemplate(
  key: string,
  body: { subject: string; html_body: string; enabled: boolean }
): Promise<void> {
  return api.put(`/api/v1/admin/email_templates/${key}`, body);
}

export function resetEmailTemplate(key: string): Promise<void> {
  return api.post(`/api/v1/admin/email_templates/${key}/reset`);
}

// `subject` and `html_body` are optional — omitting them previews the
// saved version (or the default if nothing is saved). Passing them
// previews an unsaved draft without persisting.
export function previewEmailTemplate(
  key: string,
  draft?: { subject: string; html_body: string }
): Promise<EmailTemplatePreview> {
  return api.post<EmailTemplatePreview>(`/api/v1/admin/email_templates/${key}/preview`, draft || {});
}

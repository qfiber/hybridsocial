import { api } from './client.js';
import type {
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
  InstancePurgePreview
} from './types.js';

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

export function suspendUser(id: string): Promise<void> {
  return api.post(`/api/v1/admin/users/${id}/suspend`);
}

export function unsuspendUser(id: string): Promise<void> {
  return api.post(`/api/v1/admin/users/${id}/unsuspend`);
}

export function warnUser(id: string, message: string): Promise<void> {
  return api.post(`/api/v1/admin/users/${id}/warn`, { message });
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
  return api.get('/api/v1/admin/ip_blocks');
}

export function createIpBlock(block: Omit<IpBlock, 'id' | 'created_at'>): Promise<IpBlock> {
  return api.post('/api/v1/admin/ip_blocks', block);
}

export function deleteIpBlock(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/ip_blocks/${id}`);
}

// Federation
export function getKnownInstances(params?: Record<string, string>): Promise<PaginatedResponse<KnownInstance>> {
  return api.get('/api/v1/admin/instances', params);
}

export function getFederationPolicies(): Promise<FederationPolicy[]> {
  return api.get('/api/v1/admin/federation/policies');
}

export function createFederationPolicy(policy: Omit<FederationPolicy, 'id' | 'created_at' | 'updated_at'>): Promise<FederationPolicy> {
  return api.post('/api/v1/admin/federation/policies', policy);
}

export function updateFederationPolicy(id: string, policy: Partial<FederationPolicy>): Promise<FederationPolicy> {
  return api.put(`/api/v1/admin/federation/policies/${id}`, policy);
}

export function deleteFederationPolicy(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/federation/policies/${id}`);
}

export function getDeliveryQueueStats(): Promise<DeliveryQueueStats> {
  return api.get('/api/v1/admin/federation/delivery');
}

export function retryDeliveryQueue(): Promise<void> {
  return api.post('/api/v1/admin/federation/delivery/retry');
}

// Settings
export function getAdminSettings(): Promise<AdminSetting[]> {
  return api.get('/api/v1/admin/settings');
}

export function updateAdminSettings(settings: { key: string; value: string }[]): Promise<AdminSetting[]> {
  return api.put('/api/v1/admin/settings', { settings });
}

// Theme
export function getAdminTheme(): Promise<AdminThemeConfig> {
  return api.get('/api/v1/admin/theme');
}

export function saveAdminTheme(theme: AdminThemeConfig): Promise<AdminThemeConfig> {
  return api.put('/api/v1/admin/theme', theme);
}

export function uploadLogo(file: File): Promise<{ url: string }> {
  return api.upload('/api/v1/admin/theme/logo', file);
}

export function uploadFavicon(file: File): Promise<{ url: string }> {
  return api.upload('/api/v1/admin/theme/favicon', file);
}

// Backups
export function getBackups(): Promise<Backup[]> {
  return api.get('/api/v1/admin/backups');
}

export function createBackup(passphrase?: string): Promise<Backup> {
  return api.post('/api/v1/admin/backups', { passphrase });
}

// Audit Log
export function getAuditLog(params?: Record<string, string>): Promise<PaginatedResponse<AuditLogEntry>> {
  return api.get('/api/v1/admin/audit_log', params);
}

// Relays
export function getRelays(): Promise<Relay[]> {
  return api.get('/api/v1/admin/relays');
}

export function addRelay(inboxUrl: string): Promise<Relay> {
  return api.post('/api/v1/admin/relays', { inbox_url: inboxUrl });
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

// Verifications
export interface VerificationRequest {
  id: string;
  type: string;
  status: string;
  metadata: Record<string, unknown>;
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
  return api.get('/api/v1/admin/verifications', params).then((r: { data: VerificationRequest[] }) => r.data);
}

export function approveVerification(id: string): Promise<VerificationRequest> {
  return api.post(`/api/v1/admin/verifications/${id}/approve`).then((r: { data: VerificationRequest }) => r.data);
}

export function rejectVerification(id: string): Promise<VerificationRequest> {
  return api.post(`/api/v1/admin/verifications/${id}/reject`).then((r: { data: VerificationRequest }) => r.data);
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
  return api.get('/api/v1/admin/site_pages').then((r: { data: SitePage[] }) => r.data);
}

export function getSitePage(id: string): Promise<SitePage> {
  return api.get(`/api/v1/admin/site_pages/${id}`).then((r: { data: SitePage }) => r.data);
}

export function updateSitePage(id: string, attrs: { title?: string; body_markdown?: string; published?: boolean }): Promise<SitePage> {
  return api.put(`/api/v1/admin/site_pages/${id}`, attrs).then((r: { data: SitePage }) => r.data);
}

export function seedSitePages(): Promise<SitePage[]> {
  return api.post('/api/v1/admin/site_pages/seed').then((r: { data: SitePage[] }) => r.data);
}

// Webhooks
export function getWebhooks(): Promise<Webhook[]> {
  return api.get('/api/v1/admin/webhooks');
}

export function createWebhook(webhook: { url: string; events: string[]; secret?: string; enabled?: boolean }): Promise<Webhook> {
  return api.post('/api/v1/admin/webhooks', webhook);
}

export function updateWebhook(id: string, webhook: Partial<{ url: string; events: string[]; secret: string; enabled: boolean }>): Promise<Webhook> {
  return api.put(`/api/v1/admin/webhooks/${id}`, webhook);
}

export function deleteWebhook(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/webhooks/${id}`);
}

// Appeals
export function getAppeals(params?: Record<string, string>): Promise<Appeal[]> {
  return api.get('/api/v1/admin/appeals', params);
}

export function approveAppeal(id: string, response?: string): Promise<Appeal> {
  return api.post(`/api/v1/admin/appeals/${id}/approve`, { response });
}

export function rejectAppeal(id: string, response?: string): Promise<Appeal> {
  return api.post(`/api/v1/admin/appeals/${id}/reject`, { response });
}

// Moderation Notes
export function getModerationNotes(accountId: string): Promise<ModerationNote[]> {
  return api.get(`/api/v1/admin/users/${accountId}/notes`);
}

export function createModerationNote(accountId: string, content: string): Promise<ModerationNote> {
  return api.post(`/api/v1/admin/users/${accountId}/notes`, { content });
}

export function deleteModerationNote(id: string): Promise<void> {
  return api.delete(`/api/v1/admin/notes/${id}`);
}

// Moderation Queue
export function getModerationQueue(params?: Record<string, string>): Promise<ModerationQueueItem[]> {
  return api.get('/api/v1/admin/moderation_queue', params);
}

export function getModerationQueueStats(): Promise<ModerationQueueStats> {
  return api.get('/api/v1/admin/moderation_queue/stats');
}

export function approveQueueItem(id: string): Promise<ModerationQueueItem> {
  return api.post(`/api/v1/admin/moderation_queue/${id}/approve`);
}

export function rejectQueueItem(id: string, reason?: string): Promise<ModerationQueueItem> {
  return api.post(`/api/v1/admin/moderation_queue/${id}/reject`, { reason });
}

export function escalateQueueItem(id: string): Promise<ModerationQueueItem> {
  return api.post(`/api/v1/admin/moderation_queue/${id}/escalate`);
}

// Invite Codes
export function getInvites(): Promise<InviteCode[]> {
  return api.get('/api/v1/admin/invites');
}

export function createInvite(params: { max_uses?: number; expires_at?: string }): Promise<InviteCode> {
  return api.post('/api/v1/admin/invites', params);
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
  return api.post(`/api/v1/admin/statuses/${postId}/ban_media`);
}

// Instance Purge
export function purgeInstancePreview(domain: string): Promise<InstancePurgePreview> {
  return api.get(`/api/v1/admin/instances/${encodeURIComponent(domain)}/purge_preview`);
}

export function purgeInstanceContent(domain: string): Promise<void> {
  return api.post(`/api/v1/admin/instances/${encodeURIComponent(domain)}/purge`);
}

// Admin Post Actions
export function adminGetPost(id: string): Promise<Record<string, unknown>> {
  return api.get(`/api/v1/admin/statuses/${id}`);
}

export function adminDeletePost(id: string, reason?: string): Promise<void> {
  return api.delete(`/api/v1/admin/statuses/${id}`, { reason });
}

export function adminForceSensitive(id: string): Promise<void> {
  return api.post(`/api/v1/admin/statuses/${id}/force_sensitive`);
}

export function adminRemoveSensitive(id: string): Promise<void> {
  return api.post(`/api/v1/admin/statuses/${id}/remove_sensitive`);
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

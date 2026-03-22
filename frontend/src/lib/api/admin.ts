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
  PaginatedResponse
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

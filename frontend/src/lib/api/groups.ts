import { api } from './client.js';
import type { Group, Identity, Post, PaginatedResponse } from './types.js';

export interface GroupDetail extends Group {
  rules: string[];
  join_policy: 'open' | 'approval' | 'invite';
  pending_request: boolean;
}

export interface GroupMember {
  // Always present from the backend (serialize_member returns member.id); it's
  // the membership id used for role/ban/remove endpoints (/members/:mid).
  id: string;
  identity_id?: string;
  account: Identity;
  role: 'owner' | 'admin' | 'moderator' | 'member';
  joined_at: string;
}

export interface GroupApplication {
  id: string;
  account: Identity;
  answers: { question: string; answer: string }[];
  created_at: string;
}

export interface GroupSettings {
  name?: string;
  description?: string;
  visibility?: 'public' | 'private' | 'secret';
  join_policy?: 'open' | 'approval' | 'invite';
  avatar_url?: string | null;
  header_url?: string | null;
  rules?: string[];
}

export interface GroupInvite {
  id: string;
  group_id: string;
  invited_by: string;
  invited_id: string;
  invited: Identity | null;
  inviter: Identity | null;
  status: 'pending' | 'accepted' | 'declined';
  created_at: string;
}

export function getGroups(filter: 'member' | 'discover' = 'member', cursor?: string): Promise<PaginatedResponse<Group>> {
  const params: Record<string, string> = { filter };
  if (cursor) params.cursor = cursor;
  return api.get('/api/v1/groups', params);
}

export function getGroup(id: string): Promise<GroupDetail> {
  return api.get(`/api/v1/groups/${id}`);
}

// Each question is stored as an object on the backend (jsonb array of maps).
// The settings UI works with plain strings and converts at the call site.
export interface ScreeningQuestion {
  text: string;
}

export interface GroupScreening {
  questions: ScreeningQuestion[];
  min_account_age_days: number;
  require_profile_image: boolean;
}

export function getGroupScreening(id: string): Promise<GroupScreening> {
  return api.get(`/api/v1/groups/${id}/screening`);
}

// Screening config has its own endpoint (PATCH /groups/:id/screening). The
// generic updateGroup (PATCH /groups/:id) does NOT persist screening — the
// backend's group changeset drops the key — so it must be saved separately.
export function updateGroupScreening(id: string, data: GroupScreening): Promise<GroupScreening> {
  return api.patch(`/api/v1/groups/${id}/screening`, data);
}

export type FederationMode = 'local_only' | 'public_federated';

export function createGroup(data: {
  name: string;
  description?: string;
  visibility?: string;
  join_policy?: string;
  federation_mode?: FederationMode;
}): Promise<GroupDetail> {
  return api.post('/api/v1/groups', data);
}

export function updateGroup(id: string, data: GroupSettings): Promise<GroupDetail> {
  return api.patch(`/api/v1/groups/${id}`, data);
}

export function deleteGroup(id: string): Promise<void> {
  return api.delete(`/api/v1/groups/${id}`);
}

export function joinGroup(id: string): Promise<{ status: 'joined' | 'pending' }> {
  return api.post(`/api/v1/groups/${id}/join`);
}

export function leaveGroup(id: string): Promise<void> {
  return api.post(`/api/v1/groups/${id}/leave`);
}

export function getGroupMembers(id: string, cursor?: string): Promise<PaginatedResponse<GroupMember>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get(`/api/v1/groups/${id}/members`, params);
}

export function getGroupTimeline(id: string, cursor?: string): Promise<PaginatedResponse<Post>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get(`/api/v1/timelines/group/${id}`, params);
}

export function getGroupApplications(id: string, cursor?: string): Promise<PaginatedResponse<GroupApplication>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get(`/api/v1/groups/${id}/applications`, params);
}

export function approveApplication(groupId: string, applicationId: string): Promise<void> {
  return api.post(`/api/v1/groups/${groupId}/applications/${applicationId}/approve`);
}

export function rejectApplication(groupId: string, applicationId: string): Promise<void> {
  return api.post(`/api/v1/groups/${groupId}/applications/${applicationId}/reject`);
}

export function inviteToGroup(groupId: string, accountId: string): Promise<void> {
  // Backend reads `invited_id` (matches the GroupInvite schema column);
  // sending `account_id` made every invite fail validation silently
  // since the changeset's validate_required([:invited_id]) kicked in.
  return api.post(`/api/v1/groups/${groupId}/invite`, { invited_id: accountId });
}

export function listGroupInvites(groupId: string): Promise<GroupInvite[]> {
  return api.get(`/api/v1/groups/${groupId}/invites`);
}

export function cancelGroupInvite(groupId: string, inviteId: string): Promise<void> {
  return api.delete(`/api/v1/groups/${groupId}/invites/${inviteId}`);
}

// The `:mid` path param is the GroupMember membership id (member.id), NOT the
// account id — get_member_by_id looks up by GroupMember.id on the backend.
export function updateMemberRole(groupId: string, memberId: string, role: string): Promise<void> {
  return api.patch(`/api/v1/groups/${groupId}/members/${memberId}`, { role });
}

export function banMember(groupId: string, memberId: string): Promise<void> {
  return api.post(`/api/v1/groups/${groupId}/members/${memberId}/ban`);
}

export function searchGroups(query: string, cursor?: string): Promise<PaginatedResponse<Group>> {
  const params: Record<string, string> = { q: query };
  if (cursor) params.cursor = cursor;
  return api.get('/api/v1/groups/search', params);
}

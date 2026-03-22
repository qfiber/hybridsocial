import { api } from './client.js';
import type { Group, Identity, Post, PaginatedResponse } from './types.js';

export interface GroupDetail extends Group {
  rules: string[];
  join_policy: 'open' | 'approval' | 'invite';
  pending_request: boolean;
}

export interface GroupMember {
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
  rules?: string[];
  screening?: {
    questions?: string[];
    min_account_age_days?: number;
    require_profile_image?: boolean;
  };
}

export function getGroups(filter: 'member' | 'discover' = 'member', cursor?: string): Promise<PaginatedResponse<Group>> {
  const params: Record<string, string> = { filter };
  if (cursor) params.cursor = cursor;
  return api.get('/api/v1/groups', params);
}

export function getGroup(id: string): Promise<GroupDetail> {
  return api.get(`/api/v1/groups/${id}`);
}

export function createGroup(data: { name: string; description?: string; visibility?: string; join_policy?: string }): Promise<GroupDetail> {
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
  return api.post(`/api/v1/groups/${groupId}/invite`, { account_id: accountId });
}

export function updateMemberRole(groupId: string, accountId: string, role: string): Promise<void> {
  return api.patch(`/api/v1/groups/${groupId}/members/${accountId}`, { role });
}

export function banMember(groupId: string, accountId: string): Promise<void> {
  return api.post(`/api/v1/groups/${groupId}/members/${accountId}/ban`);
}

export function searchGroups(query: string, cursor?: string): Promise<PaginatedResponse<Group>> {
  const params: Record<string, string> = { q: query };
  if (cursor) params.cursor = cursor;
  return api.get('/api/v1/groups/search', params);
}

import { api } from './client.js';
import type { Identity, Post, PaginatedResponse } from './types.js';

export interface List {
  id: string;
  name: string;
  title?: string; // alias for compatibility
  member_count: number;
  created_at: string;
  updated_at: string;
}

export function getLists(): Promise<List[]> {
  return api.get('/api/v1/lists');
}

export function getList(id: string): Promise<List> {
  return api.get(`/api/v1/lists/${id}`);
}

export function createList(title: string): Promise<List> {
  return api.post('/api/v1/lists', { name: title });
}

export function updateList(id: string, title: string): Promise<List> {
  return api.put(`/api/v1/lists/${id}`, { name: title });
}

export function deleteList(id: string): Promise<void> {
  return api.delete(`/api/v1/lists/${id}`);
}

export function getListTimeline(id: string, cursor?: string): Promise<PaginatedResponse<Post>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get(`/api/v1/timelines/list/${id}`, params);
}

export function getListMembers(id: string, cursor?: string): Promise<PaginatedResponse<Identity>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get(`/api/v1/lists/${id}/accounts`, params);
}

export function addListMember(id: string, accountId: string): Promise<void> {
  return api.post(`/api/v1/lists/${id}/accounts`, { account_ids: [accountId] });
}

export function removeListMember(id: string, accountId: string): Promise<void> {
  return api.delete(`/api/v1/lists/${id}/accounts`, { account_ids: [accountId] });
}

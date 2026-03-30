import { api } from './client.js';
import type { Identity, Relationship, PaginatedResponse } from './types.js';

export function getAccount(id: string): Promise<Identity> {
  return api.get(`/api/v1/accounts/${id}`);
}

export function lookupAccount(handle: string): Promise<Identity> {
  // Strip leading @ if present
  const clean = handle.startsWith('@') ? handle.slice(1) : handle;
  return api.get('/api/v1/accounts/lookup', { handle: clean });
}

export function updateAccount(data: {
  display_name?: string;
  bio?: string;
  is_locked?: boolean;
  is_bot?: boolean;
  show_badge?: boolean;
  default_visibility?: string;
}): Promise<Identity> {
  return api.patch('/api/v1/accounts/update_credentials', data);
}

export async function updateAvatar(file: File): Promise<Identity> {
  const { uploadMedia } = await import('./media.js');
  const media = await uploadMedia(file);
  return api.patch('/api/v1/accounts/update_credentials', { avatar_url: media.url });
}

export async function updateHeader(file: File): Promise<Identity> {
  const { uploadMedia } = await import('./media.js');
  const media = await uploadMedia(file);
  return api.patch('/api/v1/accounts/update_credentials', { header_url: media.url });
}

export function getFollowers(id: string, cursor?: string): Promise<PaginatedResponse<Identity>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get(`/api/v1/accounts/${id}/followers`, params);
}

export function getFollowing(id: string, cursor?: string): Promise<PaginatedResponse<Identity>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get(`/api/v1/accounts/${id}/following`, params);
}

export function follow(id: string): Promise<Relationship> {
  return api.post(`/api/v1/accounts/${id}/follow`);
}

export function unfollow(id: string): Promise<Relationship> {
  return api.post(`/api/v1/accounts/${id}/unfollow`);
}

export function block(id: string): Promise<Relationship> {
  return api.post(`/api/v1/accounts/${id}/block`);
}

export function unblock(id: string): Promise<Relationship> {
  return api.post(`/api/v1/accounts/${id}/unblock`);
}

export function mute(id: string, notifications?: boolean): Promise<Relationship> {
  return api.post(`/api/v1/accounts/${id}/mute`, { notifications });
}

export function unmute(id: string): Promise<Relationship> {
  return api.post(`/api/v1/accounts/${id}/unmute`);
}

export function getRelationships(ids: string[]): Promise<Relationship[]> {
  return api.get('/api/v1/accounts/relationships', { ids: ids.join(',') });
}

export function getRelationship(id: string): Promise<Relationship> {
  return api.get<Relationship[]>('/api/v1/accounts/relationships', { id }).then((rels) => {
    return rels[0] || { id, following: false, followed_by: false, blocking: false, muting: false };
  });
}

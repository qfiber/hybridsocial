import { api } from './client.js';
import type { Post, PaginatedResponse } from './types.js';

export interface CreatePostRequest {
  content: string;
  visibility?: Post['visibility'];
  sensitive?: boolean;
  spoiler_text?: string;
  language?: string;
  parent_id?: string;
  quote_id?: string;
  media_ids?: string[];
  poll?: {
    options: string[];
    expires_in: number;
    multiple?: boolean;
  };
}

export function createPost(data: CreatePostRequest): Promise<Post> {
  return api.post('/api/v1/statuses', data);
}

export function getPost(id: string): Promise<Post> {
  return api.get(`/api/v1/statuses/${id}`);
}

export function editPost(id: string, data: { content?: string; sensitive?: boolean; spoiler_text?: string; media_ids?: string[] }): Promise<Post> {
  return api.put(`/api/v1/statuses/${id}`, data);
}

export function deletePost(id: string): Promise<void> {
  return api.delete(`/api/v1/statuses/${id}`);
}

export function getPostContext(id: string): Promise<{ ancestors: Post[]; descendants: Post[] }> {
  return api.get(`/api/v1/statuses/${id}/context`);
}

export function boostPost(id: string): Promise<Post> {
  return api.post(`/api/v1/statuses/${id}/boost`);
}

export function unboostPost(id: string): Promise<Post> {
  return api.post(`/api/v1/statuses/${id}/unboost`);
}

export function reactToPost(id: string, emoji: string): Promise<Post> {
  return api.post(`/api/v1/statuses/${id}/react`, { emoji });
}

export function removeReaction(id: string): Promise<Post> {
  return api.post(`/api/v1/statuses/${id}/unreact`);
}

export function bookmarkPost(id: string): Promise<Post> {
  return api.post(`/api/v1/statuses/${id}/bookmark`);
}

export function unbookmarkPost(id: string): Promise<Post> {
  return api.post(`/api/v1/statuses/${id}/unbookmark`);
}

export function pinPost(id: string): Promise<Post> {
  return api.post(`/api/v1/statuses/${id}/pin`);
}

export function unpinPost(id: string): Promise<Post> {
  return api.post(`/api/v1/statuses/${id}/unpin`);
}

export function getScheduledPosts(): Promise<Post[]> {
  return api.get('/api/v1/scheduled_statuses');
}

export function updateScheduledPost(id: string, data: { scheduled_at?: string; content?: string; visibility?: string }): Promise<Post> {
  return api.put(`/api/v1/scheduled_statuses/${id}`, data);
}

export function deleteScheduledPost(id: string): Promise<void> {
  return api.delete(`/api/v1/scheduled_statuses/${id}`);
}

export function getAccountStatuses(accountId: string, params?: {
  only_media?: boolean;
  pinned?: boolean;
  cursor?: string;
  exclude_replies?: boolean;
  only_direct?: boolean;
  max_id?: string;
}): Promise<Post[]> {
  const query: Record<string, string> = {};
  if (params?.only_media) query.only_media = 'true';
  if (params?.pinned) query.pinned = 'true';
  if (params?.exclude_replies) query.exclude_replies = 'true';
  if (params?.only_direct) query.only_direct = 'true';
  if (params?.cursor) query.max_id = params.cursor;
  if (params?.max_id) query.max_id = params.max_id;
  return api.get(`/api/v1/accounts/${accountId}/statuses`, query);
}

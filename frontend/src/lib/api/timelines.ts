import { api } from './client.js';
import type { Post, PaginatedResponse } from './types.js';

interface TimelineParams {
  cursor?: string;
  limit?: string;
}

function buildParams(params?: TimelineParams): Record<string, string> {
  const query: Record<string, string> = {};
  if (params?.cursor) query.cursor = params.cursor;
  if (params?.limit) query.limit = params.limit;
  return query;
}

export function getHomeTimeline(params?: TimelineParams): Promise<PaginatedResponse<Post>> {
  return api.get('/api/v1/timelines/home', buildParams(params));
}

export function getPublicTimeline(params?: TimelineParams & { local?: boolean }): Promise<PaginatedResponse<Post>> {
  const query = buildParams(params);
  if (params?.local) query.local = 'true';
  return api.get('/api/v1/timelines/public', query);
}

export function getHashtagTimeline(tag: string, params?: TimelineParams): Promise<PaginatedResponse<Post>> {
  return api.get(`/api/v1/timelines/tag/${encodeURIComponent(tag)}`, buildParams(params));
}

export function getListTimeline(listId: string, params?: TimelineParams): Promise<PaginatedResponse<Post>> {
  return api.get(`/api/v1/timelines/list/${listId}`, buildParams(params));
}

export function getGroupTimeline(groupId: string, params?: TimelineParams): Promise<PaginatedResponse<Post>> {
  return api.get(`/api/v1/timelines/group/${groupId}`, buildParams(params));
}

export function getBookmarks(params?: TimelineParams): Promise<PaginatedResponse<Post>> {
  return api.get('/api/v1/bookmarks', buildParams(params));
}

import { api } from './client.js';
import type { SearchResults } from './types.js';

export function search(query: string, params?: {
  type?: 'accounts' | 'statuses' | 'hashtags';
  resolve?: boolean;
  limit?: number;
  offset?: number;
}): Promise<SearchResults> {
  const q: Record<string, string> = { q: query };
  if (params?.type) q.type = params.type;
  if (params?.resolve) q.resolve = 'true';
  if (params?.limit) q.limit = String(params.limit);
  if (params?.offset) q.offset = String(params.offset);
  return api.get('/api/v1/search', q);
}

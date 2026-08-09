import { api } from './client.js';
import type { InstanceInfo, TrendingTag, Identity } from './types.js';

export function getInstanceInfo(): Promise<InstanceInfo> {
  return api.get('/api/v1/instance');
}

export function getTrending(): Promise<TrendingTag[]> {
  return api.get<TrendingTag[]>('/api/v1/trends/tags').catch(() => []);
}

/** Trending accounts — personal profiles ranked by recent engagement + followers. */
export function getTrendingAccounts(): Promise<Identity[]> {
  return api.get<Identity[]>('/api/v1/trends/accounts').catch(() => []);
}

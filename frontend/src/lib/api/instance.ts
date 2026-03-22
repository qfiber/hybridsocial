import { api } from './client.js';
import type { InstanceInfo, TrendingTag } from './types.js';

export function getInstanceInfo(): Promise<InstanceInfo> {
  return api.get('/api/v1/instance');
}

export function getTrending(): Promise<TrendingTag[]> {
  return api.get<TrendingTag[]>('/api/v1/trends/tags').catch(() => []);
}

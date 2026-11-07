import { api } from './client.js';
import type { InstanceInfo } from './types.js';

export function getInstanceInfo(): Promise<InstanceInfo> {
  return api.get('/api/v1/instance');
}


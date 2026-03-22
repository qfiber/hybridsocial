import { api } from './client.js';
import type { Announcement } from './types.js';

export function getAnnouncements(): Promise<Announcement[]> {
  return api.get('/api/v1/announcements');
}

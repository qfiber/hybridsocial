import { api } from './client.js';

export interface Session {
  id: string;
  device_name: string;
  ip_address: string | null;
  location: string | null;
  user_agent: string | null;
  last_active_at: string | null;
  created_at: string;
  current: boolean;
}

export function getSessions(): Promise<Session[]> {
  return api.get('/api/v1/auth/sessions').then((r: { data: Session[] }) => r.data);
}

export function revokeSession(id: string): Promise<void> {
  return api.delete(`/api/v1/auth/sessions/${id}`);
}

export function revokeOtherSessions(): Promise<{ count: number }> {
  return api.post('/api/v1/auth/sessions/revoke_others');
}

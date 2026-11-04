import { writable } from 'svelte/store';

// Client-side mirror of the backend sudo window. Cleared when:
//  - the admin layout mounts and the status endpoint returns sudo=false
//  - any admin API call responds 403 auth.sudo_required
//  - the stored expiry passes (a setInterval in the layout watches this)
//
// Set to the expires_at ISO string when the sudo challenge succeeds, and
// updated from x-sudo-expires-at on every gated response as the window rolls.
export const sudoExpiresAt = writable<string | null>(null);

export function isSudoValid(expiresAt: string | null): boolean {
  if (!expiresAt) return false;
  return new Date(expiresAt).getTime() > Date.now();
}

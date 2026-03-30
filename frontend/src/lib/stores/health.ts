import { writable, derived } from 'svelte/store';
import { browser } from '$app/environment';
import { api } from '$lib/api/client.js';

interface HealthState {
  serverReachable: boolean;
  sessionValid: boolean;
  lastCheck: number;
  checking: boolean;
}

const state = writable<HealthState>({
  serverReachable: true,
  sessionValid: true,
  lastCheck: Date.now(),
  checking: false,
});

export const serverReachable = derived(state, ($s) => $s.serverReachable);
export const sessionValid = derived(state, ($s) => $s.sessionValid);
export const healthState = derived(state, ($s) => $s);

let interval: ReturnType<typeof setInterval> | null = null;
let consecutiveFailures = 0;

async function check() {
  state.update((s) => ({ ...s, checking: true }));

  try {
    // Ping the instance endpoint (public, lightweight)
    const response = await fetch(
      `${import.meta.env.VITE_API_URL || 'http://localhost:4000'}/api/v1/instance`,
      { method: 'GET', signal: AbortSignal.timeout(8000) }
    );

    if (response.ok) {
      consecutiveFailures = 0;
      state.update((s) => ({
        ...s,
        serverReachable: true,
        lastCheck: Date.now(),
        checking: false,
      }));
    } else {
      consecutiveFailures++;
      state.update((s) => ({
        ...s,
        serverReachable: consecutiveFailures < 2,
        lastCheck: Date.now(),
        checking: false,
      }));
    }
  } catch {
    consecutiveFailures++;
    state.update((s) => ({
      ...s,
      // Only mark unreachable after 2 consecutive failures (avoid flicker)
      serverReachable: consecutiveFailures < 2,
      lastCheck: Date.now(),
      checking: false,
    }));
  }

  // Check session validity (only if server is reachable and we have a user)
  try {
    const token = api.getAccessToken();
    if (token) {
      const res = await fetch(
        `${import.meta.env.VITE_API_URL || 'http://localhost:4000'}/api/v1/accounts/verify_credentials`,
        {
          method: 'GET',
          headers: { Authorization: `Bearer ${token}` },
          credentials: 'include',
          signal: AbortSignal.timeout(8000),
        }
      );

      if (res.status === 401 || res.status === 403) {
        state.update((s) => ({ ...s, sessionValid: false }));
      } else if (res.ok) {
        state.update((s) => ({ ...s, sessionValid: true }));
      }
    }
  } catch {
    // Network error — don't invalidate session
  }
}

export function startHealthCheck() {
  if (!browser || interval) return;

  // Initial check after 5s (give auth time to initialize)
  setTimeout(check, 5000);

  // Then every 30s
  interval = setInterval(check, 30_000);
}

export function stopHealthCheck() {
  if (interval) {
    clearInterval(interval);
    interval = null;
  }
}

export function markSessionExpired() {
  state.update((s) => ({ ...s, sessionValid: false }));
}

export function markSessionValid() {
  state.update((s) => ({ ...s, sessionValid: true }));
}

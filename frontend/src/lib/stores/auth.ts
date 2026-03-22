import { writable, derived, get } from 'svelte/store';
import { api } from '$lib/api/client.js';
import { getCurrentUser } from '$lib/api/auth.js';
import type { Identity, AuthTokens } from '$lib/api/types.js';
import { browser } from '$app/environment';

interface AuthState {
  user: Identity | null;
  accessToken: string | null;
  refreshToken: string | null;
  loading: boolean;
  initialized: boolean;
}

const STORAGE_KEY = 'hybridsocial_auth';

function loadFromStorage(): Partial<AuthState> {
  if (!browser) return {};
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return {};
    const data = JSON.parse(raw);
    return {
      user: data.user || null,
      accessToken: data.accessToken || null,
      refreshToken: data.refreshToken || null
    };
  } catch {
    return {};
  }
}

function saveToStorage(state: AuthState): void {
  if (!browser) return;
  try {
    sessionStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({
        user: state.user,
        accessToken: state.accessToken,
        refreshToken: state.refreshToken
      })
    );
  } catch {
    // Storage full or unavailable
  }
}

function clearStorage(): void {
  if (!browser) return;
  sessionStorage.removeItem(STORAGE_KEY);
}

const stored = loadFromStorage();

const initialState: AuthState = {
  user: stored.user ?? null,
  accessToken: stored.accessToken ?? null,
  refreshToken: stored.refreshToken ?? null,
  loading: false,
  initialized: false
};

// Sync tokens to API client on init
if (initialState.accessToken && initialState.refreshToken) {
  api.setTokens(initialState.accessToken, initialState.refreshToken);
}

export const authStore = writable<AuthState>(initialState);

export const currentUser = derived(authStore, ($s) => $s.user);
export const isLoggedIn = derived(authStore, ($s) => !!$s.user);
export const isAuthLoading = derived(authStore, ($s) => $s.loading);

export function hasPermission(permission: string): boolean {
  const state = get(authStore);
  return state.user?.permissions?.includes(permission) ?? false;
}

export function hasAnyPermission(...permissions: string[]): boolean {
  const state = get(authStore);
  if (!state.user?.permissions) return false;
  return permissions.some((p) => state.user!.permissions.includes(p));
}

export function isStaff(): boolean {
  const state = get(authStore);
  return (state.user?.roles?.length ?? 0) > 0;
}

let refreshTimer: ReturnType<typeof setTimeout> | null = null;

function scheduleRefresh(expiresIn: number): void {
  if (refreshTimer) clearTimeout(refreshTimer);
  // Refresh 60 seconds before expiry, minimum 10s
  const delay = Math.max((expiresIn - 60) * 1000, 10000);
  refreshTimer = setTimeout(async () => {
    const state = get(authStore);
    if (!state.refreshToken) return;
    try {
      const { refreshTokens } = await import('$lib/api/auth.js');
      const tokens = await refreshTokens(state.refreshToken);
      setTokens(tokens);
    } catch {
      clearAuth();
    }
  }, delay);
}

export function setTokens(tokens: AuthTokens): void {
  api.setTokens(tokens.access_token, tokens.refresh_token);
  authStore.update((s) => {
    const next = {
      ...s,
      accessToken: tokens.access_token,
      refreshToken: tokens.refresh_token
    };
    saveToStorage(next);
    return next;
  });
  if (tokens.expires_in) {
    scheduleRefresh(tokens.expires_in);
  }
}

export function setUser(user: Identity): void {
  authStore.update((s) => {
    const next = { ...s, user };
    saveToStorage(next);
    return next;
  });
}

export function clearAuth(): void {
  if (refreshTimer) clearTimeout(refreshTimer);
  api.clearTokens();
  clearStorage();

  // Disconnect SSE notifications
  try {
    const { disconnectNotificationStream } = require('$lib/stores/notifications.js');
    disconnectNotificationStream();
  } catch {}

  // Clear all session-related storage
  if (browser) {
    sessionStorage.clear();
    // Clear any cached identity from Valkey (frontend side)
    localStorage.removeItem('hybridsocial_preferences');
  }

  authStore.set({
    user: null,
    accessToken: null,
    refreshToken: null,
    loading: false,
    initialized: true
  });
}

export async function initAuth(): Promise<void> {
  const state = get(authStore);
  if (state.initialized) return;
  if (!state.accessToken) {
    authStore.update((s) => ({ ...s, initialized: true }));
    return;
  }

  authStore.update((s) => ({ ...s, loading: true }));
  try {
    const user = await getCurrentUser();
    authStore.update((s) => {
      const next = { ...s, user, loading: false, initialized: true };
      saveToStorage(next);
      return next;
    });
  } catch {
    clearAuth();
  }
}

// Wire up token refresh callback on the API client
api.setOnTokenRefresh((access, refresh) => {
  authStore.update((s) => {
    const next = { ...s, accessToken: access, refreshToken: refresh };
    saveToStorage(next);
    return next;
  });
});

api.setOnAuthFailure(() => {
  clearAuth();
});

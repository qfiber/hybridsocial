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

const USER_KEY = 'hybridsocial_user';

function loadCachedUser(): Identity | null {
  if (!browser) return null;
  try {
    const raw = localStorage.getItem(USER_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function saveCachedUser(user: Identity | null): void {
  if (!browser) return;
  try {
    if (user) {
      localStorage.setItem(USER_KEY, JSON.stringify(user));
    } else {
      localStorage.removeItem(USER_KEY);
    }
  } catch {}
}

const initialState: AuthState = {
  user: loadCachedUser(),
  accessToken: null,
  refreshToken: null,
  loading: false,
  initialized: false
};

export const authStore = writable<AuthState>(initialState);
export const currentUser = derived(authStore, ($s) => $s.user);
export const isLoggedIn = derived(authStore, ($s) => !!$s.user);
export const isAuthLoading = derived(authStore, ($s) => $s.loading);
export const isAdmin = derived(authStore, ($s) => $s.user?.is_admin === true);
export const isStaffMember = derived(authStore, ($s) => ($s.user?.roles?.length ?? 0) > 0 || $s.user?.is_admin === true);

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

// ---- Token Refresh ----

let refreshTimer: ReturnType<typeof setTimeout> | null = null;

function scheduleRefresh(expiresIn: number): void {
  if (refreshTimer) clearTimeout(refreshTimer);
  // Refresh 2 minutes before expiry, minimum 30s
  const delay = Math.max((expiresIn - 120) * 1000, 30_000);
  refreshTimer = setTimeout(() => attemptRefresh(), delay);
}

async function attemptRefresh(retries = 2): Promise<void> {
  const state = get(authStore);
  // Need either in-memory token or a cached user (cookie will be sent automatically)
  if (!state.refreshToken && !state.user) return;

  try {
    const { refreshTokens } = await import('$lib/api/auth.js');
    // Send refresh token in body if we have it, otherwise rely on httpOnly cookie
    const tokens = await refreshTokens(state.refreshToken || '');
    setTokens(tokens);
  } catch (err: unknown) {
    const { ApiError } = await import('$lib/api/client.js');
    const isAuthError = err instanceof ApiError && (err.status === 401 || err.status === 403);

    if (isAuthError) {
      clearAuth();
    } else if (retries > 0) {
      setTimeout(() => attemptRefresh(retries - 1), 5_000);
    } else {
      // Network issue — don't log out, try again later
      scheduleRefresh(60);
    }
  }
}

// ---- Public API ----

export function setTokens(tokens: AuthTokens): void {
  // Store tokens in memory + API client (for Authorization header)
  // Cookies are set by the backend response automatically
  api.setTokens(tokens.access_token, tokens.refresh_token);
  authStore.update((s) => ({
    ...s,
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token
  }));
  if (tokens.expires_in) {
    scheduleRefresh(tokens.expires_in);
  }
}

export function setUser(user: Identity): void {
  saveCachedUser(user);
  authStore.update((s) => ({ ...s, user }));
}

export function clearAuth(): void {
  if (refreshTimer) clearTimeout(refreshTimer);
  api.clearTokens();
  saveCachedUser(null);

  try {
    const { disconnectNotificationStream } = require('$lib/stores/notifications.js');
    disconnectNotificationStream();
  } catch {}

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

  // No cached user — nothing to restore
  if (!state.user) {
    authStore.update((s) => ({ ...s, initialized: true }));
    return;
  }

  // Have cached user — validate with server (cookies sent automatically)
  authStore.update((s) => ({ ...s, loading: true }));
  try {
    const user = await getCurrentUser();
    saveCachedUser(user);
    authStore.update((s) => ({
      ...s,
      user,
      loading: false,
      initialized: true
    }));
    scheduleRefresh(900);
  } catch (err: unknown) {
    const { ApiError } = await import('$lib/api/client.js');
    const isAuthError = err instanceof ApiError && (err.status === 401 || err.status === 403);

    if (!isAuthError) {
      // Network error — keep cached user, retry later
      authStore.update((s) => ({ ...s, loading: false, initialized: true }));
      scheduleRefresh(30);
      return;
    }

    // 401 — access token expired, try refresh (cookie sent automatically)
    try {
      const { refreshTokens } = await import('$lib/api/auth.js');
      const tokens = await refreshTokens('');
      setTokens(tokens);

      const user = await getCurrentUser();
      saveCachedUser(user);
      authStore.update((s) => ({
        ...s,
        user,
        loading: false,
        initialized: true
      }));
      scheduleRefresh(tokens.expires_in || 900);
    } catch (refreshErr: unknown) {
      const isRefreshAuthError = refreshErr instanceof (await import('$lib/api/client.js')).ApiError
        && (refreshErr.status === 401 || refreshErr.status === 403);

      if (isRefreshAuthError) {
        // Both access and refresh tokens invalid — truly logged out
        clearAuth();
      } else {
        // Network error on refresh — keep cached user
        authStore.update((s) => ({ ...s, loading: false, initialized: true }));
        scheduleRefresh(30);
      }
    }
  }
}

// Wire up API client callbacks
api.setOnTokenRefresh((access, refresh) => {
  authStore.update((s) => ({
    ...s,
    accessToken: access,
    refreshToken: refresh
  }));
});

api.setOnAuthFailure(async () => {
  try {
    const { markSessionExpired } = await import('$lib/stores/health.js');
    markSessionExpired();
  } catch { /* */ }
  // Delay clearAuth so the banner shows briefly
  setTimeout(() => clearAuth(), 3000);
});

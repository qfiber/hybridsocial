import { writable, derived, get } from 'svelte/store';
import { api } from '$lib/api/client.js';
import { getCurrentUser } from '$lib/api/auth.js';
import type { Identity } from '$lib/api/types.js';
import { browser } from '$app/environment';

interface AuthState {
  user: Identity | null;
  loading: boolean;
  initialized: boolean;
}

const initialState: AuthState = {
  user: null,
  loading: false,
  initialized: false
};

export const authStore = writable<AuthState>(initialState);
export const currentUser = derived(authStore, ($s) => $s.user);
export const isLoggedIn = derived(authStore, ($s) => !!$s.user);
export const isAuthLoading = derived(authStore, ($s) => $s.loading);
export const isAdmin = derived(authStore, ($s) => $s.user?.is_admin === true);
export const isStaffMember = derived(authStore, ($s) => ($s.user?.roles?.length ?? 0) > 0 || $s.user?.is_admin === true);

// Signals to the ConnectionBanner
export const sessionExpired = writable(false);
export const serverReachable = writable(true);

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
  if (!state.user) return;

  try {
    const { refreshTokens } = await import('$lib/api/auth.js');
    await refreshTokens();
    // Cookies updated by the response — just schedule next refresh
    scheduleRefresh(900);
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

export function setUser(user: Identity): void {
  authStore.update((s) => ({ ...s, user }));
}

export function clearAuth(): void {
  if (refreshTimer) clearTimeout(refreshTimer);

  try {
    import('$lib/stores/notifications.js').then(({ disconnectNotificationStream }) => {
      disconnectNotificationStream();
    });
  } catch {}

  authStore.set({
    user: null,
    loading: false,
    initialized: true
  });
}

export async function initAuth(): Promise<void> {
  const state = get(authStore);
  if (state.initialized) return;

  if (!browser) {
    authStore.update((s) => ({ ...s, initialized: true }));
    return;
  }

  // Try to authenticate with httpOnly cookies
  authStore.update((s) => ({ ...s, loading: true }));
  try {
    const user = await getCurrentUser();
    authStore.update((s) => ({
      ...s,
      user,
      loading: false,
      initialized: true
    }));
    scheduleRefresh(900);

    // Sync server preferences to local stores
    if ((user as any).locale) {
      try {
        const { setLocale } = await import('$lib/utils/i18n.js');
        await setLocale((user as any).locale);
        const { locale } = await import('$lib/stores/i18n.js');
        locale.set((user as any).locale);
      } catch { /* i18n not critical */ }
    }
    // Sync all preferences from server
    try {
      const { applyServerPreferences } = await import('$lib/stores/preferences.js');
      applyServerPreferences(
        (user as any).preferences || {},
        (user as any).default_visibility
      );
    } catch { /* preferences not critical */ }
  } catch (err: unknown) {
    const { ApiError } = await import('$lib/api/client.js');
    const isAuthError = err instanceof ApiError && (err.status === 401 || err.status === 403);

    if (isAuthError) {
      // No valid session — user is not logged in
      authStore.update((s) => ({ ...s, user: null, loading: false, initialized: true }));
    } else {
      // Network error — can't determine auth state, mark initialized but no user
      authStore.update((s) => ({ ...s, loading: false, initialized: true }));
      scheduleRefresh(30);
    }
  }
}

// Wire up API client callbacks
api.setOnTokenRefreshed(() => {
  scheduleRefresh(900);
});

api.setOnAuthFailure(() => {
  sessionExpired.set(true);
  // Delay clearAuth so the banner shows briefly
  setTimeout(() => clearAuth(), 3000);
});

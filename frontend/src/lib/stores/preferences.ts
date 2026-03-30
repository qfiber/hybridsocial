import { writable, get } from 'svelte/store';
import type { UserPreferences } from '$lib/api/types.js';
import { browser } from '$app/environment';

const STORAGE_KEY = 'hybridsocial_preferences';

const defaults: UserPreferences = {
  feed_algorithm: 'chronological',
  compact_mode: false,
  sidebar_position: 'left',
  auto_play_media: true,
  default_visibility: 'public',
  default_language: null,
  comment_style: 'threaded'
};

function loadPreferences(): UserPreferences {
  if (!browser) return defaults;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return defaults;
    return { ...defaults, ...JSON.parse(raw) };
  } catch {
    return defaults;
  }
}

function saveLocal(prefs: UserPreferences): void {
  if (!browser) return;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
  } catch {
    // Storage unavailable
  }
}

export const preferencesStore = writable<UserPreferences>(loadPreferences());

/**
 * Update preferences locally and persist to server.
 * Local storage is kept as a cache for instant load.
 */
export function updatePreferences(partial: Partial<UserPreferences>): void {
  preferencesStore.update((current) => {
    const next = { ...current, ...partial };
    saveLocal(next);
    return next;
  });

  // Persist to server in the background
  syncToServer(partial);
}

/**
 * Load preferences from server response and apply to store.
 * Called on auth init when /auth/me returns preferences.
 */
export function applyServerPreferences(serverPrefs: Record<string, any>, defaultVisibility?: string): void {
  preferencesStore.update((current) => {
    const merged = { ...current };

    // Apply individual server fields
    if (defaultVisibility) merged.default_visibility = defaultVisibility as any;

    // Apply preferences map from server
    if (serverPrefs) {
      if (serverPrefs.feed_algorithm) merged.feed_algorithm = serverPrefs.feed_algorithm;
      if (serverPrefs.compact_mode !== undefined) merged.compact_mode = serverPrefs.compact_mode;
      if (serverPrefs.sidebar_position) merged.sidebar_position = serverPrefs.sidebar_position;
      if (serverPrefs.auto_play_media !== undefined) merged.auto_play_media = serverPrefs.auto_play_media;
      if (serverPrefs.default_language !== undefined) merged.default_language = serverPrefs.default_language;
      if (serverPrefs.comment_style) merged.comment_style = serverPrefs.comment_style;
    }

    saveLocal(merged);
    return merged;
  });
}

let syncTimeout: ReturnType<typeof setTimeout> | null = null;

function syncToServer(partial: Partial<UserPreferences>): void {
  // Debounce server sync to avoid rapid writes
  if (syncTimeout) clearTimeout(syncTimeout);
  syncTimeout = setTimeout(async () => {
    try {
      const { api } = await import('$lib/api/client.js');
      const prefs = get(preferencesStore);

      // Send as a preferences map
      await api.patch('/api/v1/accounts/update_credentials', {
        preferences: {
          feed_algorithm: prefs.feed_algorithm,
          compact_mode: prefs.compact_mode,
          sidebar_position: prefs.sidebar_position,
          auto_play_media: prefs.auto_play_media,
          default_language: prefs.default_language,
          comment_style: prefs.comment_style,
        },
        ...(partial.default_visibility ? { default_visibility: partial.default_visibility } : {}),
      });
    } catch {
      // Server sync failed — local is still saved
    }
  }, 1000);
}

export function resetPreferences(): void {
  saveLocal(defaults);
  preferencesStore.set(defaults);
  syncToServer(defaults);
}

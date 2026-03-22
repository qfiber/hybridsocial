import { writable } from 'svelte/store';
import type { UserPreferences } from '$lib/api/types.js';
import { browser } from '$app/environment';

const STORAGE_KEY = 'hybridsocial_preferences';

const defaults: UserPreferences = {
  feed_algorithm: 'chronological',
  compact_mode: false,
  sidebar_position: 'left',
  auto_play_media: true,
  default_visibility: 'public',
  default_language: null
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

function savePreferences(prefs: UserPreferences): void {
  if (!browser) return;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
  } catch {
    // Storage unavailable
  }
}

export const preferencesStore = writable<UserPreferences>(loadPreferences());

export function updatePreferences(partial: Partial<UserPreferences>): void {
  preferencesStore.update((current) => {
    const next = { ...current, ...partial };
    savePreferences(next);
    return next;
  });
}

export function resetPreferences(): void {
  savePreferences(defaults);
  preferencesStore.set(defaults);
}

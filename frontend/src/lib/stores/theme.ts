import { writable } from 'svelte/store';
import type { ThemeConfig } from '$lib/api/types.js';
import { browser } from '$app/environment';

export const themeStore = writable<ThemeConfig | null>(null);

const PROPERTY_MAP: Record<keyof ThemeConfig, string> = {
  color_primary: '--color-primary',
  color_primary_hover: '--color-primary-hover',
  color_primary_soft: '--color-primary-soft',
  color_secondary: '--color-secondary',
  color_accent: '--color-accent',
  gradient_start: '--gradient-start',
  gradient_end: '--gradient-end',
  gradient_direction: '--gradient-direction'
};

export function applyTheme(config: ThemeConfig | null): void {
  themeStore.set(config);
  if (!browser || !config) return;

  const root = document.documentElement;
  for (const [key, cssVar] of Object.entries(PROPERTY_MAP)) {
    const value = config[key as keyof ThemeConfig];
    if (value) {
      root.style.setProperty(cssVar, value);
    }
  }
}

export function clearTheme(): void {
  themeStore.set(null);
  if (!browser) return;

  const root = document.documentElement;
  for (const cssVar of Object.values(PROPERTY_MAP)) {
    root.style.removeProperty(cssVar);
  }
}

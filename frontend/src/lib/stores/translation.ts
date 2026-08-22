import { writable, derived, get } from 'svelte/store';
import { api } from '$lib/api/client.js';
import { locale } from './i18n.js';

// Per-post translation preferences and instance capability.
//
// The target language defaults to the interface locale, but the user can pin a
// different one in Settings — e.g. browse the UI in English yet translate posts
// into Arabic. The choice is a per-device client preference (localStorage),
// mirroring how the interface locale and theme are stored; it never leaves the
// browser. Whether the Translate action is offered at all depends on the admin
// having configured a backend, surfaced via /instance/info.

const TARGET_KEY = 'hs_translate_target';

// '' means "follow the interface language"; otherwise a fixed language code.
function readTarget(): string {
  if (typeof localStorage === 'undefined') return '';
  try {
    return localStorage.getItem(TARGET_KEY) ?? '';
  } catch {
    return '';
  }
}

export const translationTarget = writable<string>(readTarget());
export const translationEnabled = writable<boolean>(false);

export function setTranslationTarget(code: string): void {
  translationTarget.set(code);
  try {
    if (code) localStorage.setItem(TARGET_KEY, code);
    else localStorage.removeItem(TARGET_KEY);
  } catch {
    /* private mode / storage disabled — keep the in-memory value */
  }
}

// The language a Translate request should target: the explicit override, or the
// current interface locale when following it. Reactive so the button relabels
// when either the override or the UI language changes.
export const effectiveTranslationTarget = derived(
  [translationTarget, locale],
  ([$target, $locale]) => $target || $locale,
);

export function currentTranslationTarget(): string {
  return get(translationTarget) || get(locale);
}

let loaded = false;

// Fetch the instance capability once per session. Safe to call repeatedly.
export async function loadTranslationConfig(): Promise<void> {
  if (loaded) return;
  loaded = true;
  try {
    const info = await api.get<{ translation_enabled?: boolean }>('/api/v1/instance/info');
    translationEnabled.set(!!info.translation_enabled);
  } catch {
    // Leave disabled — a failed probe just means no Translate button, which is
    // the safe default (the endpoint enforces it server-side regardless).
  }
}

// Auto-probe on first import in the browser so the button is ready without any
// component having to remember to initialise it.
if (typeof window !== 'undefined') {
  void loadTranslationConfig();
}

import { writable, derived } from 'svelte/store';
import { t as translate, setLocale as setI18nLocale, getLocale, initI18n, isLocaleRtl, getAvailableLocales } from '$lib/utils/i18n.js';

export const locale = writable<string>(getLocale());
export const isRtl = derived(locale, ($locale) => isLocaleRtl($locale));
export const availableLocales = writable<{ code: string; name: string; nativeName: string; rtl?: boolean }[]>([]);

/**
 * Reactive translation function.
 */
export const t = derived(locale, () => {
  return (key: string, params?: Record<string, string | number>): string => {
    return translate(key, params);
  };
});

export async function switchLocale(newLocale: string): Promise<void> {
  await setI18nLocale(newLocale);
  locale.set(getLocale());
}

export async function initializeI18n(): Promise<void> {
  await initI18n();
  locale.set(getLocale());
  availableLocales.set(getAvailableLocales());
}

type Translations = Record<string, string>;

let currentLocale = 'en';
let translations: Translations = {};
let loadedLocales: Record<string, Translations> = {};

const SUPPORTED_LOCALES = ['en', 'ar', 'es', 'fr', 'de', 'ja', 'zh', 'ko', 'pt', 'ru', 'fa', 'he', 'tr'];

export function t(key: string, params?: Record<string, string>): string {
  let value = translations[key] || key;
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      value = value.replace(`{${k}}`, v);
    }
  }
  return value;
}

export async function setLocale(locale: string): Promise<void> {
  if (!SUPPORTED_LOCALES.includes(locale)) {
    console.warn(`Locale "${locale}" is not supported, falling back to "en".`);
    locale = 'en';
  }

  if (loadedLocales[locale]) {
    translations = loadedLocales[locale];
    currentLocale = locale;
    return;
  }

  try {
    const module = await import(`../../locales/${locale}.json`);
    const data: Translations = module.default;
    loadedLocales[locale] = data;
    translations = data;
    currentLocale = locale;
  } catch {
    console.warn(`Failed to load locale "${locale}", falling back to "en".`);
    if (locale !== 'en') {
      await setLocale('en');
    }
  }
}

export function getLocale(): string {
  return currentLocale;
}

export function getSupportedLocales(): string[] {
  return SUPPORTED_LOCALES;
}

export function detectBrowserLocale(): string {
  if (typeof navigator === 'undefined') return 'en';
  const lang = navigator.language?.split('-')[0] || 'en';
  return SUPPORTED_LOCALES.includes(lang) ? lang : 'en';
}

export function initI18n(): Promise<void> {
  const locale = detectBrowserLocale();
  return setLocale(locale);
}

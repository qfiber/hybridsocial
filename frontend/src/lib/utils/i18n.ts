/**
 * i18n system — JSON-based, dynamic locale loading with English fallback.
 *
 * How to add a new language:
 * 1. Create a JSON file in src/locales/ (e.g. "fr.json")
 * 2. Add a metadata entry in src/locales/meta.json
 * 3. The system auto-discovers it — no code changes needed
 *
 * Missing translations fall back to English automatically.
 * Keys use dot notation: "nav.home", "auth.login", etc.
 */

type Translations = Record<string, string>;

let currentLocale = 'en';
let englishTranslations: Translations = {};
let translations: Translations = {};
let loadedLocales: Record<string, Translations> = {};
let availableLocales: { code: string; name: string; nativeName: string; rtl?: boolean }[] = [];

/**
 * Translate a key, with English fallback.
 * Supports interpolation: t("hello", { name: "Ahmad" }) → "Hello, Ahmad"
 */
export function t(key: string, params?: Record<string, string | number>): string {
  let value = translations[key] || englishTranslations[key] || key;
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      value = value.replaceAll(`{${k}}`, String(v));
    }
  }
  return value;
}

/**
 * Translate a backend error key into user-friendly message.
 * Includes hardcoded fallbacks for common errors in case i18n hasn't loaded yet.
 */
const ERROR_FALLBACKS: Record<string, string> = {
  'validation.failed': 'Please check your input and try again.',
  'auth.invalid_credentials': 'Invalid email or password.',
  'auth.unauthorized': 'You need to sign in to continue.',
  'auth.pow_required': 'Please complete the verification challenge.',
  'auth.captcha_failed': 'Captcha verification failed. Please try again.',
  'auth.email_domain_banned': 'Registration from this email domain is not allowed.',
  'auth.handle_reserved': 'This handle is reserved and cannot be used.',
  'rate_limit.exceeded': 'Too many requests. Please wait a moment.',
  'account.confirmation_required': 'Please check your email to confirm your account.',
};

export function tError(errorKey: string): string {
  const translated = t(`error.${errorKey}`);
  if (translated !== `error.${errorKey}`) return translated;
  return ERROR_FALLBACKS[errorKey] || 'Something went wrong. Please try again.';
}

/**
 * Load locale metadata from meta.json.
 * This file lists all available languages.
 */
async function loadLocaleMeta(): Promise<void> {
  try {
    const module = await import('../../locales/meta.json');
    availableLocales = module.default || [];
  } catch {
    // No meta.json — default to English only
    availableLocales = [{ code: 'en', name: 'English', nativeName: 'English' }];
  }
}

/**
 * Load a locale's translations. Returns empty object on failure.
 */
async function loadLocaleFile(locale: string): Promise<Translations> {
  if (loadedLocales[locale]) return loadedLocales[locale];

  try {
    // Dynamic import from locales directory
    const module = await import(`../../locales/${locale}.json`);
    const data: Translations = module.default;
    loadedLocales[locale] = data;
    return data;
  } catch {
    // Locale file not available — fall back to English silently
    return {};
  }
}

/**
 * Switch to a locale. Always loads English as fallback first.
 */
export async function setLocale(locale: string): Promise<void> {
  // Ensure English is loaded for fallback
  if (Object.keys(englishTranslations).length === 0) {
    englishTranslations = await loadLocaleFile('en');
    loadedLocales['en'] = englishTranslations;
  }

  if (locale === 'en') {
    translations = englishTranslations;
    currentLocale = 'en';
    return;
  }

  // Check if locale is available
  const isAvailable = availableLocales.some(l => l.code === locale) || locale === 'en';
  if (!isAvailable) {
    console.warn(`[i18n] Locale "${locale}" not found in meta.json, falling back to "en"`);
    translations = englishTranslations;
    currentLocale = 'en';
    return;
  }

  const data = await loadLocaleFile(locale);
  if (Object.keys(data).length === 0) {
    // Load failed — use English
    translations = englishTranslations;
    currentLocale = 'en';
  } else {
    translations = data;
    currentLocale = locale;
  }

  // Persist preference
  if (typeof localStorage !== 'undefined') {
    localStorage.setItem('hs_locale', locale);
  }
}

export function getLocale(): string {
  return currentLocale;
}

/**
 * Get all available locales from meta.json.
 */
export function getAvailableLocales(): typeof availableLocales {
  return availableLocales;
}

/**
 * Detect best locale from browser settings + saved preference.
 */
export function detectBrowserLocale(): string {
  if (typeof localStorage !== 'undefined') {
    const saved = localStorage.getItem('hs_locale');
    if (saved && availableLocales.some(l => l.code === saved)) return saved;
  }

  if (typeof navigator === 'undefined') return 'en';

  // Try exact match first (e.g. "pt-BR"), then base language (e.g. "pt")
  for (const lang of navigator.languages || [navigator.language]) {
    const exact = lang.toLowerCase();
    if (availableLocales.some(l => l.code === exact)) return exact;
    const base = exact.split('-')[0];
    if (availableLocales.some(l => l.code === base)) return base;
  }

  return 'en';
}

/**
 * Check if a locale is RTL.
 */
export function isLocaleRtl(locale: string): boolean {
  const meta = availableLocales.find(l => l.code === locale);
  if (meta?.rtl) return true;
  // Known RTL languages
  return ['ar', 'he', 'fa', 'ur', 'ps', 'sd', 'ku', 'yi'].includes(locale);
}

/**
 * Get translation completeness for a locale (percentage).
 */
export function getLocaleCompleteness(locale: string): number {
  const englishKeys = Object.keys(englishTranslations).length;
  if (englishKeys === 0 || locale === 'en') return 100;

  const localeData = loadedLocales[locale];
  if (!localeData) return 0;

  const translatedKeys = Object.keys(localeData).length;
  return Math.round((translatedKeys / englishKeys) * 100);
}

/**
 * Initialize i18n — load meta, detect locale, load translations.
 */
export async function initI18n(): Promise<void> {
  await loadLocaleMeta();
  const locale = detectBrowserLocale();
  await setLocale(locale);
}

const RTL_LOCALES = ['ar', 'he', 'fa', 'ur', 'ps', 'sd', 'yi', 'dv', 'ku', 'ug'];

// Unicode ranges for strong RTL characters
const RTL_CHAR_RE = /[\u0590-\u05FF\u0600-\u06FF\u0700-\u074F\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]/;

// Unicode ranges for strong LTR characters
const LTR_CHAR_RE = /[A-Za-z\u00C0-\u024F\u1E00-\u1EFF]/;

/**
 * Detect text direction based on the first strong Unicode directional character.
 */
export function detectDirection(text: string): 'rtl' | 'ltr' {
  for (const char of text) {
    if (RTL_CHAR_RE.test(char)) return 'rtl';
    if (LTR_CHAR_RE.test(char)) return 'ltr';
  }
  return 'ltr';
}

/**
 * Check if a locale code is an RTL language.
 */
export function isRtlLocale(locale: string): boolean {
  const base = locale.split('-')[0].toLowerCase();
  return RTL_LOCALES.includes(base);
}

import { writable } from 'svelte/store';
import { browser } from '$app/environment';

const CONSENT_KEY = 'hybridsocial_cookie_consent';

function loadConsent(): boolean {
  if (!browser) return false;
  return localStorage.getItem(CONSENT_KEY) === 'accepted';
}

export const cookieConsent = writable<boolean>(loadConsent());

export function acceptCookies(): void {
  if (browser) {
    localStorage.setItem(CONSENT_KEY, 'accepted');
  }
  cookieConsent.set(true);
}

export function hasConsented(): boolean {
  if (!browser) return false;
  return localStorage.getItem(CONSENT_KEY) === 'accepted';
}

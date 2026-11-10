const API_BASE = import.meta.env.VITE_API_URL || '';

// Web Push for this device.
//
// The permission prompt is only ever shown from an explicit user action
// (`enablePush`, wired to an "Enable notifications" button). It used to be
// requested automatically right after login and on every app load; browsers
// suppress or auto-deny prompts that arrive without a user gesture, and an
// unexpected prompt is easy to dismiss for good. `syncPushSubscription` is
// the silent counterpart for app start: it refreshes the subscription only
// when permission was already granted, and never prompts.

/**
 * Where push stands on this device:
 * - `unsupported`: no Push API (old browser, or iOS Safari outside a PWA);
 * - `ios-install`: iPhone/iPad — push works only once the site is added to
 *   the Home Screen and opened from there;
 * - `denied`: blocked in the browser's site settings (only the user can undo
 *   that, there);
 * - `default`: not decided yet — we may ask, from a button;
 * - `granted`: allowed.
 */
export type PushState = 'unsupported' | 'ios-install' | 'denied' | 'default' | 'granted';

function isIos(): boolean {
  const ua = navigator.userAgent;
  // iPadOS reports itself as a Mac; touch support gives it away.
  return /iPad|iPhone|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
}

function isStandalone(): boolean {
  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

export function pushState(): PushState {
  if (typeof window === 'undefined') return 'unsupported';
  const supported =
    'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  if (!supported) return isIos() && !isStandalone() ? 'ios-install' : 'unsupported';
  const permission = Notification.permission;
  return permission === 'granted' ? 'granted' : permission === 'denied' ? 'denied' : 'default';
}

/** Whether this browser currently holds a push subscription. */
export async function isPushSubscribed(): Promise<boolean> {
  if (pushState() !== 'granted') return false;
  try {
    const registration = await navigator.serviceWorker.getRegistration();
    return !!(await registration?.pushManager.getSubscription());
  } catch {
    return false;
  }
}

// Subscribe (or reuse the existing subscription) and hand it to the backend.
// Callers must only reach this with permission already granted, so
// `pushManager.subscribe` can never be the thing that pops the prompt.
async function registerSubscription(): Promise<boolean> {
  try {
    const registration = await navigator.serviceWorker.register('/sw.js');
    await navigator.serviceWorker.ready;

    let subscription = await registration.pushManager.getSubscription();
    if (!subscription) {
      const res = await fetch(`${API_BASE}/api/v1/push/vapid_key`, { credentials: 'include' });
      const { public_key } = await res.json();
      if (!public_key) return false;

      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(public_key) as BufferSource,
      });
    }

    const saved = await fetch(`${API_BASE}/api/v1/push/subscription`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ subscription: subscription.toJSON() }),
    });
    return saved.ok;
  } catch (err) {
    console.warn('Push subscription failed:', err);
    return false;
  }
}

/**
 * App start / after login: keep an already-allowed device subscribed (and
 * re-link it to the signed-in account). Never prompts.
 */
export async function syncPushSubscription(): Promise<void> {
  if (pushState() !== 'granted') return;
  await registerSubscription();
}

/**
 * From a user gesture only: ask for permission, then subscribe. Resolves to
 * the resulting state; `granted` also means the subscription was saved.
 */
export async function enablePush(): Promise<PushState> {
  const state = pushState();
  if (state === 'unsupported' || state === 'ios-install' || state === 'denied') return state;

  const permission = state === 'granted' ? 'granted' : await Notification.requestPermission();
  if (permission !== 'granted') return permission === 'denied' ? 'denied' : 'default';

  return (await registerSubscription()) ? 'granted' : 'default';
}

export async function unsubscribeFromPush(): Promise<void> {
  try {
    const registration = await navigator.serviceWorker.getRegistration();
    if (!registration) return;

    const subscription = await registration.pushManager.getSubscription();
    if (!subscription) return;

    await subscription.unsubscribe();

    await fetch(`${API_BASE}/api/v1/push/subscription`, {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ endpoint: subscription.endpoint })
    });
  } catch {
    // Silently fail unsubscribe
  }
}

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:4000';

export async function subscribeToPush(accessToken: string): Promise<boolean> {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    return false;
  }

  try {
    // Register service worker
    const registration = await navigator.serviceWorker.register('/sw.js');
    await navigator.serviceWorker.ready;

    // Get VAPID public key
    const res = await fetch(`${API_BASE}/api/v1/push/vapid_key`, {
      headers: { Authorization: `Bearer ${accessToken}` }
    });
    const { public_key } = await res.json();

    if (!public_key) return false;

    // Convert VAPID key
    const applicationServerKey = urlBase64ToUint8Array(public_key);

    // Subscribe to push
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey
    });

    // Send subscription to backend
    await fetch(`${API_BASE}/api/v1/push/subscription`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ subscription: subscription.toJSON() })
    });

    return true;
  } catch (err) {
    console.warn('Push subscription failed:', err);
    return false;
  }
}

export async function unsubscribeFromPush(accessToken: string): Promise<void> {
  try {
    const registration = await navigator.serviceWorker.getRegistration();
    if (!registration) return;

    const subscription = await registration.pushManager.getSubscription();
    if (!subscription) return;

    await subscription.unsubscribe();

    await fetch(`${API_BASE}/api/v1/push/subscription`, {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ endpoint: subscription.endpoint })
    });
  } catch {
    // Silently fail unsubscribe
  }
}

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  return Uint8Array.from([...rawData].map((char) => char.charCodeAt(0)));
}

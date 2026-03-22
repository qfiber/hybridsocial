import { writable, derived } from 'svelte/store';
import type { Notification } from '$lib/api/types.js';
import { browser } from '$app/environment';

interface NotificationState {
  items: Notification[];
  unreadCount: number;
  loading: boolean;
}

export const notificationStore = writable<NotificationState>({
  items: [],
  unreadCount: 0,
  loading: false
});

export const unreadCount = derived(notificationStore, ($s) => $s.unreadCount);
export const notifications = derived(notificationStore, ($s) => $s.items);

let eventSource: EventSource | null = null;

export function setNotifications(items: Notification[]): void {
  const unread = items.filter((n) => !n.read).length;
  notificationStore.set({ items, unreadCount: unread, loading: false });
}

export function addNotification(notification: Notification): void {
  notificationStore.update((s) => ({
    items: [notification, ...s.items],
    unreadCount: notification.read ? s.unreadCount : s.unreadCount + 1,
    loading: s.loading
  }));
}

export function markRead(id: string): void {
  notificationStore.update((s) => ({
    items: s.items.map((n) => (n.id === id ? { ...n, read: true } : n)),
    unreadCount: Math.max(0, s.unreadCount - 1),
    loading: s.loading
  }));
}

export function clearAll(): void {
  notificationStore.set({ items: [], unreadCount: 0, loading: false });
}

export function connectNotificationStream(apiBase: string, token: string): void {
  if (!browser) return;
  disconnectNotificationStream();

  // SSE streaming - use /api/v1/streaming/user endpoint
  // Note: EventSource doesn't support custom headers, so token goes as query param
  // This will fail silently if CORS or endpoint isn't ready - that's fine
  try {
    const url = `${apiBase}/api/v1/streaming/user?access_token=${encodeURIComponent(token)}`;
    eventSource = new EventSource(url);

    eventSource.addEventListener('notification', (event) => {
      try {
        const notification: Notification = JSON.parse(event.data);
        addNotification(notification);
      } catch {
        // Ignore malformed events
      }
    });

    eventSource.onerror = () => {
      // SSE connection failed — not critical, poll instead
      disconnectNotificationStream();
    };
  } catch {
    // EventSource creation failed — silently ignore
  }
}

export function disconnectNotificationStream(): void {
  if (eventSource) {
    eventSource.close();
    eventSource = null;
  }
}

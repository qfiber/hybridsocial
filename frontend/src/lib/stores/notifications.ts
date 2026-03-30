import { writable, derived } from 'svelte/store';
import type { Notification } from '$lib/api/types.js';
import { browser } from '$app/environment';
import { serverReachable } from '$lib/stores/auth.js';

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

export function connectNotificationStream(apiBase: string): void {
  if (!browser) return;
  disconnectNotificationStream();

  // SSE streaming — auth via httpOnly cookie (withCredentials sends cookies cross-origin)
  try {
    const url = `${apiBase}/api/v1/streaming/user`;
    eventSource = new EventSource(url, { withCredentials: true });

    eventSource.addEventListener('notification', (event) => {
      try {
        const notification: Notification = JSON.parse(event.data);
        addNotification(notification);
      } catch {
        // Ignore malformed events
      }
    });

    eventSource.onopen = () => {
      serverReachable.set(true);
    };

    eventSource.onerror = () => {
      serverReachable.set(false);
      disconnectNotificationStream();
      // Attempt reconnect after 10s
      setTimeout(() => connectNotificationStream(apiBase), 10_000);
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

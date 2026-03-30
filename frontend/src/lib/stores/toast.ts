import { writable } from 'svelte/store';
import { browser } from '$app/environment';

export interface Toast {
  id: string;
  message: string;
  description?: string;
  type: 'success' | 'error' | 'info' | 'warning';
  duration: number;
}

const { subscribe, update } = writable<Toast[]>([]);

export const toasts = { subscribe };

export function addToast(
  message: string,
  type: 'success' | 'error' | 'info' | 'warning' = 'info',
  duration = 5000,
  description?: string
): void {
  const id = crypto.randomUUID();
  update((all) => [...all, { id, message, description, type, duration }]);

  if (duration > 0) {
    setTimeout(() => {
      removeToast(id);
    }, duration);
  }
}

export function removeToast(id: string): void {
  update((all) => all.filter((t) => t.id !== id));
}

// Listen for toast events dispatched from non-Svelte code (e.g. API client)
if (browser) {
  window.addEventListener('toast', (e: Event) => {
    const detail = (e as CustomEvent).detail;
    if (detail?.message) {
      addToast(detail.message, detail.type || 'info', detail.duration || 5000, detail.description);
    }
  });
}

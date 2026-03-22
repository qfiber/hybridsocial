import { writable } from 'svelte/store';

export interface Toast {
  id: string;
  message: string;
  type: 'success' | 'error' | 'info';
  duration: number;
}

const { subscribe, update } = writable<Toast[]>([]);

export const toasts = { subscribe };

export function addToast(
  message: string,
  type: 'success' | 'error' | 'info' = 'info',
  duration = 5000
): void {
  const id = crypto.randomUUID();
  update((all) => [...all, { id, message, type, duration }]);

  if (duration > 0) {
    setTimeout(() => {
      removeToast(id);
    }, duration);
  }
}

export function removeToast(id: string): void {
  update((all) => all.filter((t) => t.id !== id));
}

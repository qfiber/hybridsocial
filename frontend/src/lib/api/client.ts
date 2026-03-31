import type { ApiErrorBody } from './types.js';

const API_BASE = import.meta.env.VITE_API_URL || '';

export class ApiError extends Error {
  constructor(
    public status: number,
    public body: ApiErrorBody
  ) {
    super(body.error_description || body.error);
    this.name = 'ApiError';
  }
}

interface RequestOptions {
  body?: unknown;
  params?: Record<string, string>;
  headers?: Record<string, string>;
  rawBody?: boolean;
}

class ApiClient {
  private refreshPromise: Promise<void> | null = null;
  private onAuthFailure: (() => void) | null = null;
  private onTokenRefreshed: (() => void) | null = null;

  setOnTokenRefreshed(callback: () => void): void {
    this.onTokenRefreshed = callback;
  }

  setOnAuthFailure(callback: () => void): void {
    this.onAuthFailure = callback;
  }

  async request<T>(method: string, path: string, options?: RequestOptions): Promise<T> {
    const url = new URL(`${API_BASE}${path}`, window.location.origin);
    if (options?.params) {
      for (const [key, value] of Object.entries(options.params)) {
        url.searchParams.set(key, value);
      }
    }

    const headers: Record<string, string> = {
      Accept: 'application/json',
      ...options?.headers
    };

    let fetchBody: BodyInit | undefined;
    if (options?.body !== undefined) {
      if (options.rawBody) {
        // FormData — let browser set Content-Type with boundary
        fetchBody = options.body as BodyInit;
      } else {
        headers['Content-Type'] = 'application/json';
        fetchBody = JSON.stringify(options.body);
      }
    }

    const doFetch = () =>
      fetch(url.toString(), {
        method,
        headers,
        credentials: 'include',
        body: fetchBody
      });

    let response = await doFetch();

    // Auto-refresh on 401 (httpOnly cookie sent automatically)
    if (response.status === 401 && !path.startsWith('/api/v1/auth/')) {
      await this.doRefresh();
      response = await doFetch();
    }

    if (!response.ok) {
      // Rate limit — show toast and throw
      if (response.status === 429) {
        const retryAfter = response.headers.get('retry-after');
        const waitSec = retryAfter ? parseInt(retryAfter, 10) : 10;
        this.showRateLimitToast(waitSec);
      }

      let body: ApiErrorBody;
      try {
        body = await response.json();
      } catch {
        body = { error: 'unknown_error', error_description: response.statusText };
      }
      throw new ApiError(response.status, body);
    }

    // Handle 204 No Content
    if (response.status === 204) {
      return undefined as T;
    }

    return response.json();
  }

  private async doRefresh(): Promise<void> {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    this.refreshPromise = (async () => {
      try {
        // Rely on httpOnly cookie for refresh — no token in body
        const response = await fetch(`${API_BASE}/api/v1/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'include',
          body: JSON.stringify({})
        });

        if (response.status === 401 || response.status === 403) {
          this.onAuthFailure?.();
          return;
        }

        if (!response.ok) {
          return;
        }

        // New cookies set by the response automatically
        this.onTokenRefreshed?.();
      } catch {
        // Network error — don't log out
        console.warn('Token refresh failed due to network error, will retry later');
      } finally {
        this.refreshPromise = null;
      }
    })();

    return this.refreshPromise;
  }

  private rateLimitToastCooldown = false;

  private showRateLimitToast(waitSec: number): void {
    if (this.rateLimitToastCooldown) return;
    this.rateLimitToastCooldown = true;
    // Cooldown so we don't spam toasts on burst failures
    setTimeout(() => { this.rateLimitToastCooldown = false; }, 5000);

    try {
      window.dispatchEvent(new CustomEvent('toast', {
        detail: {
          message: 'Slow down — too many requests',
          description: `Please wait ${waitSec} seconds before trying again.`,
          type: 'warning',
        }
      }));
    } catch { /* not in browser */ }
  }

  get<T>(path: string, params?: Record<string, string>): Promise<T> {
    return this.request<T>('GET', path, { params });
  }

  post<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>('POST', path, { body });
  }

  put<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>('PUT', path, { body });
  }

  patch<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>('PATCH', path, { body });
  }

  delete<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>('DELETE', path, { body });
  }

  upload<T>(path: string, file: File, fields?: Record<string, string>): Promise<T> {
    const formData = new FormData();
    formData.append('file', file);
    if (fields) {
      for (const [key, value] of Object.entries(fields)) {
        formData.append(key, value);
      }
    }
    return this.request<T>('POST', path, { body: formData, rawBody: true });
  }
}

export const api = new ApiClient();

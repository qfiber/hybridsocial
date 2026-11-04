import type { ApiErrorBody } from './types.js';
import { sudoExpiresAt } from '$lib/stores/admin-sudo.js';

const API_BASE = import.meta.env.VITE_API_URL || '';

export class ApiError extends Error {
  constructor(
    public status: number,
    public body: ApiErrorBody
  ) {
    super(firstDetailMessage(body) || body.error_description || body.error);
    this.name = 'ApiError';
  }
}

// Validation-failure responses ship the human-readable reason in
// `body.details` as `{field: [msg, ...]}`. The outer `error` code
// ("validation.failed") is useless on its own — surface the first
// field message so callers that just show `err.message` get the
// real reason.
function firstDetailMessage(body: ApiErrorBody): string | undefined {
  const details = body.details;
  if (!details || typeof details !== 'object') return undefined;
  for (const messages of Object.values(details)) {
    if (Array.isArray(messages) && messages.length > 0 && typeof messages[0] === 'string') {
      return messages[0];
    }
  }
  return undefined;
}

interface RequestOptions {
  body?: unknown;
  params?: Record<string, string>;
  headers?: Record<string, string>;
  rawBody?: boolean;
}

// Outcome of a refresh attempt, so the auth store can decide whether to
// reschedule (ok), log out (auth_failed), or retry soon (deferred).
export type RefreshResult = 'ok' | 'auth_failed' | 'deferred';

class ApiClient {
  private refreshPromise: Promise<RefreshResult> | null = null;
  private onAuthFailure: (() => void) | null = null;
  private onTokenRefreshed: ((expiresIn?: number) => void) | null = null;

  setOnTokenRefreshed(callback: (expiresIn?: number) => void): void {
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

    // Auto-refresh on 401 (httpOnly cookie sent automatically). The
    // /api/v1/auth/* exclusion keeps the refresh/login endpoints from
    // recursing; the session-bootstrap (/auth/me) refreshes explicitly
    // in the auth store instead, so it can stay silent for logged-out
    // visitors.
    if (response.status === 401 && !path.startsWith('/api/v1/auth/')) {
      const result = await this.doRefresh();
      // Refresh definitively failed → the session is dead mid-use; let
      // the app show the "session expired" banner and bounce to /login.
      if (result === 'auth_failed') this.onAuthFailure?.();
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

      // Admin step-up expired or never obtained — signal the admin layout
      // to show the sudo challenge. Throw as normal so callers can still
      // handle it, but the event lets a global listener re-gate the UI.
      if (response.status === 403 && body.error === 'auth.sudo_required') {
        try {
          window.dispatchEvent(new CustomEvent('admin-sudo-required'));
        } catch { /* not in browser */ }
      }

      throw new ApiError(response.status, body);
    }

    // RequireSudo reports the real expiry on every gated response. The
    // window rolls forward server-side, so the value from unlock goes stale.
    const sudoUntil = response.headers.get('x-sudo-expires-at');
    if (sudoUntil) sudoExpiresAt.set(sudoUntil);

    // Handle 204 No Content
    if (response.status === 204) {
      return undefined as T;
    }

    return response.json();
  }

  /**
   * Refresh the access token. Single-flight: concurrent callers (the
   * reactive 401 path below and the auth store's proactive/visibility
   * refresh) all await the SAME in-flight request, so we never present
   * the rotating refresh token twice and race its 30s rotation grace —
   * that race is what used to 401 the loser and bounce the user to
   * /login. Public so the store shares this exact lock.
   */
  async refresh(): Promise<RefreshResult> {
    return this.doRefresh();
  }

  private async doRefresh(): Promise<RefreshResult> {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    this.refreshPromise = (async (): Promise<RefreshResult> => {
      try {
        // Rely on httpOnly cookie for refresh — no token in body
        const response = await fetch(`${API_BASE}/api/v1/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'include',
          body: JSON.stringify({})
        });

        if (response.status === 401 || response.status === 403) {
          // Don't fire onAuthFailure here — the caller decides. Active-use
          // callers surface the "session expired" banner; the startup
          // bootstrap refreshes silently so anonymous visitors never see it.
          return 'auth_failed';
        }

        if (!response.ok) {
          // Server/proxy hiccup — keep the session and let the caller retry.
          return 'deferred';
        }

        // New cookies are set by the response automatically. Read the
        // fresh TTL so the store can schedule the next refresh against
        // the token's real lifetime instead of a hardcoded guess.
        let expiresIn: number | undefined;
        try {
          const body = await response.json();
          if (typeof body?.expires_in === 'number') expiresIn = body.expires_in;
        } catch {
          // Body parse is best-effort; the cookies still rotated.
        }
        this.onTokenRefreshed?.(expiresIn);
        return 'ok';
      } catch {
        // Network error — don't log out
        console.warn('Token refresh failed due to network error, will retry later');
        return 'deferred';
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

  /**
   * GET from a timer rather than from something the operator did. It still
   * needs a live sudo window on admin routes but doesn't extend it, so an
   * open tab can idle out.
   */
  poll<T>(path: string, params?: Record<string, string>): Promise<T> {
    return this.request<T>('GET', path, { params, headers: { 'x-sudo-passive': '1' } });
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

  /**
   * Upload a file and report progress as a 0..1 fraction. Uses XHR
   * because `fetch` has no upload-progress event. Falls through the
   * same 401-refresh-retry the JSON path uses, so a refresh during a
   * large upload doesn't abort the user's work.
   */
  uploadWithProgress<T>(
    path: string,
    file: File,
    fields: Record<string, string> | undefined,
    onProgress: (fraction: number) => void
  ): Promise<T> {
    const formData = new FormData();
    formData.append('file', file);
    if (fields) {
      for (const [key, value] of Object.entries(fields)) {
        formData.append(key, value);
      }
    }
    const url = new URL(`${API_BASE}${path}`, window.location.origin).toString();

    const send = (): Promise<{ status: number; body: unknown }> =>
      new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open('POST', url, true);
        xhr.withCredentials = true;
        xhr.setRequestHeader('Accept', 'application/json');
        xhr.upload.onprogress = (e) => {
          if (e.lengthComputable && e.total > 0) {
            onProgress(Math.min(1, e.loaded / e.total));
          }
        };
        xhr.onerror = () => reject(new TypeError('Network error during upload'));
        xhr.onabort = () => reject(new TypeError('Upload aborted'));
        xhr.onload = () => {
          let body: unknown;
          try {
            body = xhr.responseText ? JSON.parse(xhr.responseText) : undefined;
          } catch {
            body = { error: 'unknown_error', error_description: xhr.statusText };
          }
          resolve({ status: xhr.status, body });
        };
        xhr.send(formData);
      });

    return (async () => {
      let { status, body } = await send();

      if (status === 401 && !path.startsWith('/api/v1/auth/')) {
        const result = await this.doRefresh();
        if (result === 'auth_failed') this.onAuthFailure?.();
        onProgress(0);
        ({ status, body } = await send());
      }

      if (status >= 200 && status < 300) {
        onProgress(1);
        return body as T;
      }

      const errBody = (body as ApiErrorBody | undefined) ?? {
        error: 'unknown_error',
        error_description: `Upload failed (${status})`,
      };
      throw new ApiError(status, errBody);
    })();
  }
}

export const api = new ApiClient();

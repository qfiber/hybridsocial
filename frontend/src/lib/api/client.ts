import type { ApiErrorBody } from './types.js';

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:4000';

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
}

class ApiClient {
  private accessToken: string | null = null;
  private refreshToken: string | null = null;
  private refreshPromise: Promise<void> | null = null;
  private onTokenRefresh: ((access: string, refresh: string) => void) | null = null;
  private onAuthFailure: (() => void) | null = null;

  setTokens(access: string, refresh: string): void {
    this.accessToken = access;
    this.refreshToken = refresh;
  }

  clearTokens(): void {
    this.accessToken = null;
    this.refreshToken = null;
  }

  getAccessToken(): string | null {
    return this.accessToken;
  }

  setOnTokenRefresh(callback: (access: string, refresh: string) => void): void {
    this.onTokenRefresh = callback;
  }

  setOnAuthFailure(callback: () => void): void {
    this.onAuthFailure = callback;
  }

  async request<T>(method: string, path: string, options?: RequestOptions): Promise<T> {
    const url = new URL(`${API_BASE}${path}`);
    if (options?.params) {
      for (const [key, value] of Object.entries(options.params)) {
        url.searchParams.set(key, value);
      }
    }

    const headers: Record<string, string> = {
      Accept: 'application/json',
      ...options?.headers
    };

    if (this.accessToken) {
      headers['Authorization'] = `Bearer ${this.accessToken}`;
    }

    if (options?.body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }

    let response = await fetch(url.toString(), {
      method,
      headers,
      credentials: 'include',
      body: options?.body !== undefined ? JSON.stringify(options.body) : undefined
    });

    // Auto-refresh on 401 (cookie or in-memory token)
    if (response.status === 401 && !path.startsWith('/api/v1/auth/')) {
      await this.doRefresh();
      // Retry with new token
      if (this.accessToken) {
        headers['Authorization'] = `Bearer ${this.accessToken}`;
      }
      response = await fetch(url.toString(), {
        method,
        headers,
        credentials: 'include',
        body: options?.body !== undefined ? JSON.stringify(options.body) : undefined
      });
    }

    if (!response.ok) {
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
        // Send refresh token in body if available, otherwise rely on httpOnly cookie
        const body: Record<string, string> = {};
        if (this.refreshToken) {
          body.refresh_token = this.refreshToken;
        }

        const response = await fetch(`${API_BASE}/api/v1/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'include',
          body: JSON.stringify(body)
        });

        if (response.status === 401 || response.status === 403) {
          // Refresh token is genuinely invalid — user must re-login
          this.clearTokens();
          this.onAuthFailure?.();
          return;
        }

        if (!response.ok) {
          // Server error (500, 502, etc.) — don't log out, just fail silently
          return;
        }

        const data = await response.json();
        this.accessToken = data.access_token;
        this.refreshToken = data.refresh_token;
        this.onTokenRefresh?.(data.access_token, data.refresh_token);
      } catch {
        // Network error (server down, DNS failure, etc.) — NOT an auth failure
        // Don't clear tokens or log out — the server might just be restarting
        console.warn('Token refresh failed due to network error, will retry later');
      } finally {
        this.refreshPromise = null;
      }
    })();

    return this.refreshPromise;
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

  delete<T>(path: string): Promise<T> {
    return this.request<T>('DELETE', path);
  }

  async upload<T>(path: string, file: File, fields?: Record<string, string>): Promise<T> {
    const url = new URL(`${API_BASE}${path}`);
    const formData = new FormData();
    formData.append('file', file);
    if (fields) {
      for (const [key, value] of Object.entries(fields)) {
        formData.append(key, value);
      }
    }

    const headers: Record<string, string> = {};
    if (this.accessToken) {
      headers['Authorization'] = `Bearer ${this.accessToken}`;
    }

    const response = await fetch(url.toString(), {
      method: 'POST',
      headers,
      credentials: 'include',
      body: formData
    });

    if (!response.ok) {
      let body: ApiErrorBody;
      try {
        body = await response.json();
      } catch {
        body = { error: 'upload_failed', error_description: response.statusText };
      }
      throw new ApiError(response.status, body);
    }

    return response.json();
  }
}

export const api = new ApiClient();

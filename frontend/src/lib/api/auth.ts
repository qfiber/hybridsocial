import { api } from './client.js';
import type { AuthTokens, Identity, TwoFactorSetup } from './types.js';

export interface LoginRequest {
  email: string;
  password: string;
  totp_code?: string;
}

export interface RegisterRequest {
  email: string;
  handle: string;
  password: string;
  display_name?: string;
  invite_code?: string;
  locale?: string;
}

export function login(data: LoginRequest): Promise<AuthTokens> {
  return api.post('/api/v1/auth/login', data);
}

export function register(data: RegisterRequest): Promise<AuthTokens> {
  return api.post('/api/v1/auth/register', data);
}

export function refreshTokens(refreshToken: string): Promise<AuthTokens> {
  return api.post('/api/v1/auth/refresh', { refresh_token: refreshToken });
}

export function logout(): Promise<void> {
  return api.post('/api/v1/auth/logout');
}

export function getCurrentUser(): Promise<Identity> {
  return api.get('/api/v1/auth/me');
}

export function setupTwoFactor(): Promise<TwoFactorSetup> {
  return api.post('/api/v1/auth/2fa/setup');
}

export function verifyTwoFactor(code: string): Promise<{ success: boolean }> {
  return api.post('/api/v1/auth/2fa/verify', { code });
}

export function disableTwoFactor(code: string): Promise<void> {
  return api.post('/api/v1/auth/2fa/disable', { code });
}

export function requestPasswordReset(email: string): Promise<void> {
  return api.post('/api/v1/auth/password/reset', { email });
}

export function confirmPasswordReset(token: string, password: string): Promise<void> {
  return api.post('/api/v1/auth/password/confirm', { token, password });
}

export function changePassword(currentPassword: string, newPassword: string): Promise<void> {
  return api.post('/api/v1/auth/password/change', {
    current_password: currentPassword,
    new_password: newPassword
  });
}

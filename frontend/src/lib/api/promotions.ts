import { api } from './client.js';

export interface PromotionPricing {
  price_cents: number;
  duration_days: number;
  max_duration_days: number;
  enabled: boolean;
  payment_configured: boolean;
  currency: string;
}

export interface Promotion {
  id: string;
  status: 'pending' | 'active' | 'expired' | 'cancelled';
  amount_cents: number;
  currency: string;
  duration_days: number;
  starts_at: string | null;
  expires_at: string | null;
  created_at: string;
}

export interface PromotedUser {
  id: string;
  handle: string;
  display_name: string;
  avatar_url: string | null;
  promoted: boolean;
}

export function getPromotionPricing(): Promise<PromotionPricing> {
  return api.get<{ data: PromotionPricing }>('/api/v1/promotions/pricing').then((r) => r.data);
}

export function getPromotedUsers(): Promise<PromotedUser[]> {
  return api.get<{ data: PromotedUser[] }>('/api/v1/promotions/promoted').then((r) => r.data);
}

export function purchasePromotion(): Promise<{ data: Promotion; message: string }> {
  return api.post('/api/v1/promotions');
}

export function getMyPromotion(): Promise<{ data: Promotion | null; pricing?: PromotionPricing }> {
  return api.get('/api/v1/promotions/me');
}

export function getPromotionHistory(): Promise<Promotion[]> {
  return api.get<{ data: Promotion[] }>('/api/v1/promotions/history').then((r) => r.data);
}

export function formatPrice(cents: number, currency: string = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency
  }).format(cents / 100);
}

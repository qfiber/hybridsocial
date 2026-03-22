import { api } from './client.js';

export interface FundingMethod {
  id: string;
  platform: string;
  display_text: string;
  url: string | null;
  wallet_address: string | null;
  enabled: boolean;
  goal_amount: number | null;
  current_amount: number | null;
}

export function getFunding(): Promise<FundingMethod[]> {
  return api.get<FundingMethod[]>('/api/v1/instance/funding').catch(() => []);
}

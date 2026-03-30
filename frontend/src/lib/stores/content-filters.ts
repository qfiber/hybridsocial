import { writable, get } from 'svelte/store';
import { api } from '$lib/api/client.js';

interface ContentFilter {
  id: string;
  phrase: string;
  context: string[];
  action: 'warn' | 'hide';
  whole_word: boolean;
  expires_at: string | null;
}

export interface FilterResult {
  action: 'warn' | 'hide';
  filter: ContentFilter;
}

const filters = writable<ContentFilter[]>([]);
let loaded = false;

export async function loadFilters(): Promise<void> {
  if (loaded) return;
  try {
    const data = await api.get<ContentFilter[]>('/api/v1/accounts/filters');
    filters.set(data);
    loaded = true;
  } catch {
    // Not logged in or filters unavailable
  }
}

export function reloadFilters(): void {
  loaded = false;
  loadFilters();
}

/**
 * Check if a post matches any content filter.
 * Returns the most restrictive matching filter result, or null.
 */
export function matchFilters(
  content: string | null | undefined,
  spoilerText: string | null | undefined,
  context: string
): FilterResult | null {
  const allFilters = get(filters);
  if (!allFilters.length || !content) return null;

  const text = `${spoilerText || ''} ${content}`.toLowerCase();
  let result: FilterResult | null = null;

  for (const filter of allFilters) {
    // Check context
    if (!filter.context.includes(context)) continue;

    // Check expiry
    if (filter.expires_at && new Date(filter.expires_at) < new Date()) continue;

    const phrase = filter.phrase.toLowerCase();

    let matched = false;
    if (filter.whole_word) {
      const regex = new RegExp(`\\b${escapeRegex(phrase)}\\b`, 'i');
      matched = regex.test(text);
    } else {
      matched = text.includes(phrase);
    }

    if (matched) {
      // 'hide' takes priority over 'warn'
      if (filter.action === 'hide') {
        return { action: 'hide', filter };
      }
      if (!result) {
        result = { action: 'warn', filter };
      }
    }
  }

  return result;
}

function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export { filters as contentFilters };

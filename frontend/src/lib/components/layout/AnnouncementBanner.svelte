<script lang="ts">
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';
  import type { Announcement } from '$lib/api/types.js';

  const DISMISSED_KEY = 'hybridsocial_dismissed_announcements';

  let announcements: Announcement[] = $state([]);
  let dismissedIds: Set<string> = $state(new Set());

  let visible = $derived(
    announcements.filter((a) => !dismissedIds.has(a.id))
  );

  function loadDismissed(): Set<string> {
    if (!browser) return new Set();
    try {
      const raw = localStorage.getItem(DISMISSED_KEY);
      if (!raw) return new Set();
      return new Set(JSON.parse(raw));
    } catch {
      return new Set();
    }
  }

  function saveDismissed(ids: Set<string>) {
    if (!browser) return;
    try {
      localStorage.setItem(DISMISSED_KEY, JSON.stringify([...ids]));
    } catch {
      // Storage unavailable
    }
  }

  function dismiss(id: string) {
    const next = new Set(dismissedIds);
    next.add(id);
    dismissedIds = next;
    saveDismissed(next);
  }

  onMount(async () => {
    dismissedIds = loadDismissed();
    try {
      const { getAnnouncements } = await import('$lib/api/announcements.js');
      const result = await getAnnouncements();
      announcements = Array.isArray(result) ? result.filter((a) => a.published) : [];
    } catch {
      // Endpoint may not exist — fail silently
      announcements = [];
    }
  });
</script>

{#if visible.length > 0}
  <div class="announcements">
    {#each visible as announcement (announcement.id)}
      <div class="announcement-banner" role="status">
        <div class="announcement-content">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" class="announcement-icon">
            <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
            <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
          </svg>
          <p class="announcement-text">{announcement.content}</p>
        </div>
        <button
          type="button"
          class="announcement-dismiss"
          onclick={() => dismiss(announcement.id)}
          aria-label="Dismiss announcement"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
    {/each}
  </div>
{/if}

<style>
  .announcements {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-block-end: var(--space-4);
  }

  .announcement-banner {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    background: var(--color-primary-soft);
    border: 1px solid var(--color-primary);
    border-radius: var(--radius-lg);
  }

  .announcement-content {
    display: flex;
    align-items: flex-start;
    gap: var(--space-2);
    flex: 1;
    min-width: 0;
  }

  .announcement-icon {
    flex-shrink: 0;
    color: var(--color-primary);
    margin-block-start: 2px;
  }

  .announcement-text {
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: var(--leading-relaxed);
  }

  .announcement-dismiss {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    background: transparent;
    border: none;
    border-radius: var(--radius-full);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
    padding: 0;
  }

  .announcement-dismiss:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }
</style>

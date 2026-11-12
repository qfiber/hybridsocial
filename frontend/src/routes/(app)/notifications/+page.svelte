<script lang="ts">
  import PushOptIn from '$lib/components/notification/PushOptIn.svelte';
  import { onMount } from 'svelte';
  import type { Notification } from '$lib/api/types.js';
  import { getNotifications, markAllNotificationsRead } from '$lib/api/notifications.js';
  import { setNotifications, markRead, markAllLocal } from '$lib/stores/notifications.js';
  import { markNotificationRead } from '$lib/api/notifications.js';
  import NotificationItem from '$lib/components/notification/NotificationItem.svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import Skeleton from '$lib/components/ui/Skeleton.svelte';
  import InfiniteScroll from '$lib/components/ui/InfiniteScroll.svelte';
  import { instanceName } from '$lib/stores/instance.js';

  let items: Notification[] = $state([]);
  let loading = $state(true);
  let loadingMore = $state(false);
  let hasMore = $state(true);
  let cursor: string | null = $state(null);
  let activeTab = $state('all');

  const tabs = [
    { id: 'all', label: 'All' },
    { id: 'mention', label: 'Mentions' },
    { id: 'reply', label: 'Replies' },
    { id: 'follow', label: 'Follows' },
    { id: 'reaction', label: 'Reactions' },
  ];

  let typeFilter = $derived.by(() => {
    switch (activeTab) {
      case 'mention':
        return ['mention'];
      case 'reply':
        return ['reply', 'quote'];
      case 'follow':
        return ['follow', 'follow_request'];
      case 'reaction':
        // "Reactions" in the UI bucket covers every positive
        // engagement on your post that isn't a reply/mention.
        return ['favourite', 'reaction', 'boost'];
      default:
        return undefined;
    }
  });

  async function loadNotifications(reset = false) {
    if (reset) {
      items = [];
      cursor = null;
      hasMore = true;
      loading = true;
    } else {
      loadingMore = true;
    }

    try {
      const params: { cursor?: string; types?: string[] } = {};
      if (cursor) params.cursor = cursor;
      if (typeFilter) params.types = typeFilter;

      const result = await getNotifications(params);
      // Backend now returns {data, next_cursor, prev_cursor}. Older
      // builds returned a bare array — keep that fallback so a
      // mid-deploy stale frontend doesn't break.
      const data: Notification[] = Array.isArray(result) ? result : (result as any).data || [];
      const nextCursor: string | null = Array.isArray(result)
        ? (data.length > 0 ? data[data.length - 1]?.id : null)
        : (result as any).next_cursor ?? null;
      if (reset) {
        items = data;
        setNotifications(data);
      } else {
        // Defense-in-depth dedupe — the new server pagination shouldn't
        // emit the boundary row twice, but a duplicate id in the {#each}
        // block crashes Svelte, and we'd rather drop a row than render
        // nothing.
        const seen = new Set(items.map((n) => n.id));
        const fresh = data.filter((n) => !seen.has(n.id));
        items = [...items, ...fresh];
      }
      cursor = nextCursor;
      hasMore = nextCursor !== null;
    } catch {
      // Handle error silently
    } finally {
      loading = false;
      loadingMore = false;
    }
  }

  async function handleMarkAllRead() {
    try {
      await markAllNotificationsRead();
      items = items.map((n) => ({ ...n, read: true }));
      // markAllLocal (rather than setNotifications) so the read-all
      // also broadcasts to sibling tabs — see cross-tab sync in
      // stores/notifications.ts (issue #8).
      markAllLocal();
    } catch {
      // Handle error silently
    }
  }

  // Entering the notifications page is the user's "I saw it" signal
  // — clear the badge immediately so the counter in the sidebar /
  // topbar is current without requiring an explicit "mark all read"
  // click. Individual items stay visually "unread" (primary-soft
  // background) until the user clicks them so they can still spot
  // new arrivals; the server-side unread flag flips so the bell
  // doesn't re-light on refresh.
  async function clearOnEntry() {
    // Drop the bell badge to 0 immediately (server catches up below),
    // but DON'T flip the visible rows to read — they stay highlighted
    // (tinted row + unread dot) until the user clicks them, so new
    // arrivals are still spottable this session. The server-side flag
    // flips so the bell doesn't re-light on refresh.
    markAllLocal();
    try {
      await markAllNotificationsRead();
    } catch {
      /* Local badge state already cleared; next load re-syncs from DB. */
    }
  }

  // The row itself is now a real <a href>, so navigation (including
  // ctrl/cmd-click → new tab and shift-click → new window) is handled
  // by the browser. We only flip the unread bit here.
  async function handleNotificationClick(notification: Notification) {
    if (!notification.read) {
      try {
        await markNotificationRead(notification.id);
        markRead(notification.id);
        items = items.map((n) => (n.id === notification.id ? { ...n, read: true } : n));
      } catch { /* ignore */ }
    }
  }

  onMount(async () => {
    await loadNotifications(true);
    // Fire the badge clear after the list is visible so the
    // pre-existing unread styling flashes once, then settles.
    clearOnEntry();
  });

  // Reload when tab changes (not on initial mount)
  let prevTab = $state(activeTab);
  $effect(() => {
    if (activeTab !== prevTab) {
      prevTab = activeTab;
      loadNotifications(true);
    }
  });

  let hasUnread = $derived(items.some((n) => !n.read));
</script>

<svelte:head>
  <title>Notifications - {$instanceName}</title>
</svelte:head>

<div class="notifications-page">
  <div class="notifications-header">
    <h1 class="notifications-title">Notifications</h1>
    {#if hasUnread}
      <button class="btn btn-ghost btn-sm" type="button" onclick={handleMarkAllRead}>
        Mark all as read
      </button>
    {/if}
  </div>

  <PushOptIn variant="banner" />

  <Tabs {tabs} bind:active={activeTab}>
    {#if loading}
      <div class="notifications-skeleton">
        {#each Array(6) as _}
          <div class="notification-skeleton-item">
            <Skeleton width="32px" height="32px" rounded />
            <div class="notification-skeleton-body">
              <Skeleton width="28px" height="28px" rounded />
              <div class="notification-skeleton-text">
                <Skeleton width="80%" height="14px" />
                <Skeleton width="50%" height="12px" />
              </div>
            </div>
          </div>
        {/each}
      </div>
    {:else if items.length === 0}
      <div class="notifications-empty">
        <div class="notifications-empty-icon" aria-hidden="true">
          <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
            <path d="M13.73 21a2 2 0 0 1-3.46 0" />
          </svg>
        </div>
        <h2 class="notifications-empty-title">You're all caught up</h2>
        <p class="empty-text">New reactions, replies, and follows will show up here.</p>
      </div>
    {:else}
      <div class="notifications-list">
        {#each items as notification (notification.id)}
          <NotificationItem {notification} onclick={handleNotificationClick} />
        {/each}
      </div>
      <InfiniteScroll
        onLoadMore={() => loadNotifications(false)}
        loading={loadingMore}
        {hasMore}
      />
    {/if}
  </Tabs>
</div>

<style>
  .notifications-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
  }

  .notifications-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-4);
  }

  .notifications-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .notifications-list {
    display: flex;
    flex-direction: column;
    background: var(--color-surface-container-lowest, var(--color-surface));
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    overflow: hidden;
  }

  /* Hairline separator between notification rows so a long list reads
     as a structured timeline instead of a wall of similar cards.
     `:not(:last-child)` keeps the bottom edge clean against the
     wrapper's own border. */
  .notifications-list :global(.notification-item:not(:last-child)) {
    border-block-end: 1px solid var(--color-border);
    border-radius: 0;
  }

  .notifications-list :global(.notification-item:first-child) {
    border-start-start-radius: var(--radius-lg);
    border-start-end-radius: var(--radius-lg);
  }

  .notifications-list :global(.notification-item:last-child) {
    border-end-start-radius: var(--radius-lg);
    border-end-end-radius: var(--radius-lg);
  }

  .notifications-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: var(--space-16) var(--space-4);
  }

  .notifications-empty-icon {
    width: 72px;
    height: 72px;
    border-radius: var(--radius-full);
    display: grid;
    place-items: center;
    color: var(--color-primary);
    background: var(--color-secondary-container);
    box-shadow: 0 8px 24px rgba(var(--color-primary-rgb), 0.12);
    margin-block-end: var(--space-5);
  }

  .notifications-empty-title {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .empty-text {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    max-width: 320px;
    line-height: 1.55;
  }

  .notifications-skeleton {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .notification-skeleton-item {
    display: flex;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
  }

  .notification-skeleton-body {
    display: flex;
    gap: var(--space-3);
    flex: 1;
  }

  .notification-skeleton-text {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    flex: 1;
  }
</style>

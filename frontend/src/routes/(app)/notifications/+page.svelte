<script lang="ts">
  import { onMount } from 'svelte';
  import type { Notification } from '$lib/api/types.js';
  import { getNotifications, markAllNotificationsRead } from '$lib/api/notifications.js';
  import { setNotifications, markRead } from '$lib/stores/notifications.js';
  import { markNotificationRead } from '$lib/api/notifications.js';
  import NotificationItem from '$lib/components/notification/NotificationItem.svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import Skeleton from '$lib/components/ui/Skeleton.svelte';
  import InfiniteScroll from '$lib/components/ui/InfiniteScroll.svelte';

  let items: Notification[] = $state([]);
  let loading = $state(true);
  let loadingMore = $state(false);
  let hasMore = $state(true);
  let cursor: string | null = $state(null);
  let activeTab = $state('all');

  const tabs = [
    { id: 'all', label: 'All' },
    { id: 'mention', label: 'Mentions' },
    { id: 'follow', label: 'Follows' },
    { id: 'reaction', label: 'Reactions' },
  ];

  let typeFilter = $derived.by(() => {
    switch (activeTab) {
      case 'mention':
        return ['mention'];
      case 'follow':
        return ['follow', 'follow_request'];
      case 'reaction':
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
      const data: Notification[] = Array.isArray(result) ? result : (result as any).data || [];
      if (reset) {
        items = data;
        setNotifications(data);
      } else {
        items = [...items, ...data];
      }
      cursor = data.length > 0 ? data[data.length - 1]?.id : null;
      hasMore = data.length >= 20;
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
      setNotifications(items);
    } catch {
      // Handle error silently
    }
  }

  async function handleNotificationClick(notification: Notification) {
    if (!notification.read) {
      try {
        await markNotificationRead(notification.id);
        markRead(notification.id);
        items = items.map((n) => (n.id === notification.id ? { ...n, read: true } : n));
      } catch { /* ignore */ }
    }

    // Navigate based on type
    if (notification.post) {
      window.location.href = `/post/${notification.post.id}`;
    } else if (notification.type === 'follow' || notification.type === 'follow_request') {
      window.location.href = `/${notification.account.handle}`;
    }
  }

  onMount(() => {
    loadNotifications(true);
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
  <title>Notifications - HybridSocial</title>
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
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--color-text-tertiary)" stroke-width="1.5" aria-hidden="true">
          <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
          <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
        </svg>
        <p class="empty-text">No notifications yet</p>
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
  }

  .notifications-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-16) var(--space-4);
  }

  .empty-text {
    font-size: var(--text-base);
    color: var(--color-text-tertiary);
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

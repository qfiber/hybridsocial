<script lang="ts">
  import { getNotifications, markNotificationRead, markAllNotificationsRead } from '$lib/api/notifications.js';
  import { unreadCount, markRead, markAllLocal } from '$lib/stores/notifications.js';
  import NotificationItem from './NotificationItem.svelte';
  import { t } from '$lib/stores/i18n.js';
  import type { Notification } from '$lib/api/types.js';

  // The header bell opens this popover instead of navigating straight to the
  // notifications page: peek, act on, or dismiss a notification without leaving
  // the current page; a footer link goes to the full page when wanted.
  let open = $state(false);
  let loading = $state(false);
  let loadError = $state(false);
  let items = $state<Notification[]>([]);
  let loaded = false;
  let rootEl: HTMLDivElement | undefined = $state();

  const PREVIEW_LIMIT = 12;

  async function fetchRecent() {
    loading = true;
    loadError = false;
    try {
      const result = await getNotifications();
      const data: Notification[] = Array.isArray(result) ? result : ((result as any)?.data ?? []);
      items = data.slice(0, PREVIEW_LIMIT);
      loaded = true;
    } catch {
      loadError = true;
    } finally {
      loading = false;
    }
  }

  function toggle() {
    open = !open;
    // Re-fetch every open so the peek is current (the SSE stream also keeps
    // the badge live, but the list is only pulled on demand).
    if (open) fetchRecent();
  }

  // Clicking a row navigates via NotificationItem's own <a>; we just flip the
  // unread bit and close the popover.
  function onItemClick(n: Notification) {
    if (!n.read) {
      markNotificationRead(n.id).catch(() => {});
      markRead(n.id);
    }
    open = false;
  }

  // Dismiss = mark read (there's no per-notification delete) and drop it from
  // the peek. stopPropagation keeps the popover open.
  function dismiss(e: MouseEvent, n: Notification) {
    e.stopPropagation();
    e.preventDefault();
    if (!n.read) {
      markNotificationRead(n.id).catch(() => {});
      markRead(n.id);
    }
    items = items.filter((x) => x.id !== n.id);
  }

  async function markAll() {
    try {
      await markAllNotificationsRead();
    } catch {
      /* best-effort */
    }
    markAllLocal();
    items = items.map((x) => ({ ...x, read: true }));
  }

  // Close on outside click / Escape (capture so we win over row handlers).
  $effect(() => {
    if (!open) return;
    function onDoc(e: MouseEvent) {
      if (rootEl && !rootEl.contains(e.target as Node)) open = false;
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') open = false;
    }
    document.addEventListener('click', onDoc, true);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('click', onDoc, true);
      document.removeEventListener('keydown', onKey);
    };
  });
</script>

<div class="notif-bell" bind:this={rootEl}>
  <button
    type="button"
    class="header-icon-btn"
    onclick={toggle}
    aria-label={$t('notifications.title')}
    aria-haspopup="dialog"
    aria-expanded={open}
  >
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
      <path d="M13.73 21a2 2 0 0 1-3.46 0" />
    </svg>
    {#if $unreadCount > 0}
      <span class="icon-badge">{$unreadCount > 99 ? '99+' : $unreadCount}</span>
    {/if}
  </button>

  {#if open}
    <div class="notif-popover" role="dialog" aria-label="Notifications">
      <div class="notif-popover-head">
        <span class="notif-popover-title">{$t('notifications.title')}</span>
        {#if $unreadCount > 0}
          <button type="button" class="notif-linkbtn" onclick={markAll}>{$t('notifications.mark_all_read')}</button>
        {/if}
      </div>

      <div class="notif-popover-list">
        {#if loading}
          <div class="notif-popover-state">{$t('notifications.loading')}</div>
        {:else if loadError}
          <div class="notif-popover-state">
            {$t('notifications.load_error')}
            <button type="button" class="notif-linkbtn" onclick={fetchRecent}>{$t('notifications.retry')}</button>
          </div>
        {:else if items.length === 0}
          <div class="notif-popover-state">{$t('notifications.empty')}</div>
        {:else}
          {#each items as n (n.id)}
            <div class="notif-row" class:is-unread={!n.read}>
              <NotificationItem notification={n} onclick={onItemClick} />
              <button
                type="button"
                class="notif-dismiss"
                aria-label={$t('notifications.dismiss')}
                title={$t('notifications.dismiss')}
                onclick={(e) => dismiss(e, n)}
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true">
                  <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              </button>
            </div>
          {/each}
        {/if}
      </div>

      <a class="notif-popover-foot" href="/notifications" onclick={() => (open = false)}>
        {$t('notifications.view_all')}
      </a>
    </div>
  {/if}
</div>

<style>
  .notif-bell {
    position: relative;
    display: inline-flex;
  }

  /* Mirrors Header's .header-icon-btn (scoped there, so replicated here). */
  .header-icon-btn {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border: none;
    background: none;
    border-radius: var(--radius-full);
    color: var(--color-on-surface-variant);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .header-icon-btn:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .icon-badge {
    position: absolute;
    top: 4px;
    inset-inline-end: 4px;
    min-width: 18px;
    height: 18px;
    padding: 0 5px;
    font-size: 0.65rem;
    font-weight: 700;
    line-height: 18px;
    text-align: center;
    color: var(--color-on-primary);
    background: var(--color-error);
    border-radius: var(--radius-full);
    border: 2px solid var(--color-surface);
  }

  .notif-popover {
    position: absolute;
    top: 100%;
    inset-inline-end: 0;
    margin-block-start: var(--space-2);
    width: min(380px, calc(100vw - 2rem));
    max-height: min(70vh, 560px);
    display: flex;
    flex-direction: column;
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg);
    z-index: var(--z-dropdown, 1000);
    overflow: hidden;
    animation: notif-pop-in 150ms ease;
  }

  @keyframes notif-pop-in {
    from { opacity: 0; transform: translateY(-6px); }
    to { opacity: 1; transform: translateY(0); }
  }

  .notif-popover-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    padding: var(--space-3) var(--space-3) var(--space-2);
    border-block-end: 1px solid var(--color-border);
  }

  .notif-popover-title {
    font-weight: 700;
    font-size: var(--text-md, 1rem);
  }

  .notif-linkbtn {
    background: none;
    border: none;
    padding: 0;
    color: var(--color-primary);
    font-size: var(--text-sm, 0.875rem);
    cursor: pointer;
  }

  .notif-linkbtn:hover {
    text-decoration: underline;
  }

  .notif-popover-list {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
  }

  .notif-popover-state {
    padding: var(--space-6, 32px) var(--space-4, 16px);
    text-align: center;
    color: var(--color-text-secondary);
    font-size: var(--text-sm, 0.875rem);
  }

  .notif-row {
    position: relative;
  }

  .notif-row.is-unread {
    background: color-mix(in srgb, var(--color-primary) 6%, transparent);
  }

  /* The dismiss × sits over the row's top-inline-end corner; it's a sibling of
     the NotificationItem <a>, so a click hits the button, not the link. */
  .notif-dismiss {
    position: absolute;
    top: var(--space-2, 8px);
    inset-inline-end: var(--space-2, 8px);
    width: 26px;
    height: 26px;
    display: grid;
    place-items: center;
    border: none;
    border-radius: var(--radius-full);
    background: var(--color-surface);
    color: var(--color-text-tertiary);
    cursor: pointer;
    opacity: 0;
    transition: opacity 120ms ease, color 120ms ease, background 120ms ease;
  }

  .notif-row:hover .notif-dismiss,
  .notif-dismiss:focus-visible {
    opacity: 1;
  }

  .notif-dismiss:hover {
    color: var(--color-text);
    background: var(--color-surface-hover, var(--color-border));
  }

  .notif-popover-foot {
    display: block;
    padding: var(--space-3);
    text-align: center;
    font-weight: 600;
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-primary);
    text-decoration: none;
    border-block-start: 1px solid var(--color-border);
  }

  .notif-popover-foot:hover {
    background: var(--color-surface);
  }

  /* On coarse-pointer (touch) there's no hover, so keep dismiss reachable. */
  @media (pointer: coarse) {
    .notif-dismiss {
      opacity: 1;
    }

    /* On a phone the bell sits near the right edge, so an inline-end-anchored
       popover runs off the left of the screen (its start edge is clipped).
       Detach it from the bell and center it under the header as a near-
       full-width sheet so it shows completely and consistently. */
    .notif-popover {
      position: fixed;
      inset-block-start: calc(var(--header-height, 60px) + var(--space-2));
      inset-inline: 0;
      margin-inline: auto;
      width: min(420px, calc(100vw - 2 * var(--space-2)));
      max-height: min(75vh, 620px);
    }
  }
</style>

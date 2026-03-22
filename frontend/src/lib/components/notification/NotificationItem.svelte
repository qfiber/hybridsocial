<script lang="ts">
  import type { Notification } from '$lib/api/types.js';
  import { goto } from '$app/navigation';
  import { relativeTime } from '$lib/utils/time.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';

  let {
    notification,
    onclick,
  }: {
    notification: Notification;
    onclick?: (notification: Notification) => void;
  } = $props();

  let timeAgo = $derived(relativeTime(notification.created_at));
  let actorName = $derived(notification.account.display_name || notification.account.handle);

  let description = $derived.by(() => {
    switch (notification.type) {
      case 'follow':
        return 'followed you';
      case 'follow_request':
        return 'requested to follow you';
      case 'favourite':
        return 'favourited your post';
      case 'reaction':
        return 'reacted to your post';
      case 'boost':
        return 'boosted your post';
      case 'mention':
        return 'mentioned you';
      case 'poll':
        return 'A poll you voted in has ended';
      case 'update':
        return 'edited a post';
      case 'group_invite':
        return 'invited you to a group';
      default:
        return 'interacted with you';
    }
  });

  let iconPath = $derived.by(() => {
    switch (notification.type) {
      case 'follow':
      case 'follow_request':
        return 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M14 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0M22 11l-3 3-2-2';
      case 'favourite':
        return 'M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z';
      case 'reaction':
        return 'M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3zM7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3';
      case 'boost':
        return 'M17 1l4 4-4 4M3 11V9a4 4 0 0 1 4-4h14M7 23l-4-4 4-4M21 13v2a4 4 0 0 1-4 4H3';
      case 'mention':
        return 'M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z';
      case 'poll':
        return 'M18 20V10M12 20V4M6 20v-6';
      default:
        return 'M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 0 1-3.46 0';
    }
  });

  let iconColor = $derived.by(() => {
    switch (notification.type) {
      case 'follow':
      case 'follow_request':
        return 'var(--color-info)';
      case 'favourite':
        return 'var(--color-danger)';
      case 'reaction':
        return 'var(--color-warning)';
      case 'boost':
        return 'var(--color-success)';
      case 'mention':
        return 'var(--color-primary)';
      default:
        return 'var(--color-text-secondary)';
    }
  });

  function handleClick() {
    onclick?.(notification);

    // Navigate based on notification type
    switch (notification.type) {
      case 'follow':
      case 'follow_request':
        goto(`/@${notification.account.handle}`);
        break;
      case 'reaction':
      case 'boost':
      case 'favourite':
      case 'mention':
      case 'update':
      case 'poll':
        if (notification.post) {
          goto(`/post/${notification.post.id}`);
        }
        break;
      case 'group_invite':
        if (notification.post) {
          goto(`/groups/${notification.post.id}`);
        }
        break;
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleClick();
    }
  }
</script>

<div
  class="notification-item"
  class:unread={!notification.read}
  role="button"
  tabindex="0"
  onclick={handleClick}
  onkeydown={handleKeydown}
  aria-label="{actorName} {description}"
>
  <div class="notification-icon" style="color: {iconColor}">
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d={iconPath} />
    </svg>
  </div>

  <div class="notification-content">
    <div class="notification-actor">
      <Avatar src={notification.account.avatar_url} name={actorName} size="sm" />
    </div>

    <div class="notification-body">
      <p class="notification-text">
        <a href="/{notification.account.handle}" class="notification-actor-name">{actorName}</a>
        {description}
      </p>

      {#if notification.post}
        <p class="notification-preview">{notification.post.content}</p>
      {/if}

      <time class="notification-time" datetime={notification.created_at}>
        {timeAgo}
      </time>
    </div>
  </div>
</div>

<style>
  .notification-item {
    display: flex;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-lg);
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .notification-item:hover {
    background: var(--color-surface);
  }

  .notification-item:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: -2px;
  }

  .notification-item.unread {
    background: var(--color-primary-soft);
  }

  .notification-item.unread:hover {
    background: color-mix(in srgb, var(--color-primary-soft) 80%, var(--color-surface) 20%);
  }

  .notification-icon {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    padding-block-start: var(--space-1);
  }

  .notification-content {
    display: flex;
    gap: var(--space-3);
    flex: 1;
    min-width: 0;
  }

  .notification-actor {
    flex-shrink: 0;
  }

  .notification-body {
    flex: 1;
    min-width: 0;
  }

  .notification-text {
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: 1.4;
  }

  .notification-actor-name {
    font-weight: 600;
    color: var(--color-text);
    text-decoration: none;
  }

  .notification-actor-name:hover {
    text-decoration: underline;
  }

  .notification-preview {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-start: var(--space-1);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .notification-time {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-1);
    display: block;
  }
</style>

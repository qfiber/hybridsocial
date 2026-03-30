<script lang="ts">
  import type { Conversation, Identity } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';

  let {
    conversation,
    active = false,
    currentUserId = '',
    onclick
  }: {
    conversation: Conversation;
    active?: boolean;
    currentUserId?: string;
    onclick?: () => void;
  } = $props();

  let otherParticipants = $derived(
    conversation.participants.filter((p) => p.id !== currentUserId)
  );

  let displayName = $derived(
    otherParticipants.map((p) => p.display_name || p.handle).join(', ') || 'Unknown'
  );

  let avatarUser = $derived(otherParticipants[0] ?? null);

  let lastMessagePreview = $derived(
    conversation.last_message?.content
      ? conversation.last_message.content.length > 60
        ? conversation.last_message.content.slice(0, 60) + '...'
        : conversation.last_message.content
      : 'No messages yet'
  );

  let timeAgo = $derived(formatRelativeTime(conversation.updated_at));

  function formatRelativeTime(dateStr: string): string {
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffSec = Math.floor(diffMs / 1000);
    const diffMin = Math.floor(diffSec / 60);
    const diffHr = Math.floor(diffMin / 60);
    const diffDays = Math.floor(diffHr / 24);

    if (diffSec < 60) return 'now';
    if (diffMin < 60) return `${diffMin}m`;
    if (diffHr < 24) return `${diffHr}h`;
    if (diffDays < 7) return `${diffDays}d`;
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  }
</script>

<button
  type="button"
  class="conversation-item"
  class:active
  class:unread={conversation.unread_count > 0}
  onclick={onclick}
>
  <Avatar
    src={avatarUser?.avatar_url}
    name={avatarUser?.display_name || avatarUser?.handle || ''}
    size="md"
  />
  <div class="conversation-content">
    <div class="conversation-header">
      <span class="conversation-name">
        {displayName}
        {#if conversation.is_encrypted}
          <span class="material-symbols-outlined encryption-icon encrypted" title="End-to-end encrypted">lock</span>
        {:else if !conversation.is_local}
          <span class="material-symbols-outlined encryption-icon unencrypted" title="Not encrypted — federated message">lock_open</span>
        {/if}
      </span>
      <span class="conversation-time">{timeAgo}</span>
    </div>
    {#if !conversation.accepted}
      <div class="conversation-pending">Message request</div>
    {:else}
    <div class="conversation-preview">
      <span class="conversation-message">{lastMessagePreview}</span>
      {#if conversation.unread_count > 0}
        <span class="unread-badge" aria-label="{conversation.unread_count} unread messages">
          {conversation.unread_count > 99 ? '99+' : conversation.unread_count}
        </span>
      {/if}
    </div>
    {/if}
  </div>
</button>

<style>
  .conversation-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border: none;
    background: none;
    width: 100%;
    text-align: start;
    cursor: pointer;
    border-radius: var(--radius-lg);
    transition: background var(--transition-fast);
  }

  .conversation-item:hover {
    background: var(--color-surface);
  }

  .conversation-item.active {
    background: var(--color-primary-soft);
  }

  .conversation-content {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .conversation-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
  }

  .conversation-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .unread .conversation-name {
    font-weight: 700;
  }

  .conversation-time {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    flex-shrink: 0;
  }

  .conversation-preview {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .conversation-message {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
    min-width: 0;
  }

  .unread .conversation-message {
    color: var(--color-text);
    font-weight: 500;
  }

  .unread-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 20px;
    height: 20px;
    padding: 0 var(--space-1);
    border-radius: var(--radius-full);
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    font-size: 11px;
    font-weight: 700;
    line-height: 1;
    flex-shrink: 0;
  }

  .encryption-icon {
    font-size: 14px;
    vertical-align: middle;
    margin-inline-start: 4px;
  }

  .encrypted {
    color: var(--color-success, #22c55e);
  }

  .unencrypted {
    color: var(--color-warning, #f59e0b);
  }

  .conversation-pending {
    font-size: var(--text-xs);
    color: var(--color-warning, #f59e0b);
    font-weight: 600;
    margin-block-start: 2px;
  }
</style>

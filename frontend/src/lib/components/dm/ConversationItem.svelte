<script lang="ts">
  import { t } from '$lib/stores/i18n.js';
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
    // Backend's participant payload is the join-row, where `id` is the
    // conversation_participant row id (per-conversation) and
    // `identity_id` is the actual viewer identity. Compare against
    // the latter — comparing `p.id` to `currentUserId` (identity uuid)
    // never matches, so the row never filters out the viewer and the
    // sidebar ends up showing their own avatar + name.
    conversation.participants.filter((p) => p.identity_id !== currentUserId)
  );

  let displayName = $derived(
    otherParticipants.map((p) => p.display_name || p.acct || p.handle).join(', ') || 'Unknown'
  );

  let avatarUser = $derived(otherParticipants[0] ?? null);

  // A message with no text (a voice note, a photo…) is still a message:
  // label it by its attachment instead of claiming "No messages yet".
  const MEDIA_PREVIEW: Record<string, string> = {
    audio: 'dm.preview_voice',
    image: 'dm.preview_image',
    video: 'dm.preview_video',
    file: 'dm.preview_file',
  };

  let lastMessagePreview = $derived.by(() => {
    const last = conversation.last_message;
    const text = last?.content?.trim();
    if (text) return text.length > 60 ? text.slice(0, 60) + '...' : text;
    if (last) return $t(MEDIA_PREVIEW[last.media_type ?? 'file'] ?? 'dm.preview_file');
    return $t('dm.no_messages');
  });

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
        {#if conversation.encryption_status === 'e2ee'}
          <span
            class="material-symbols-outlined encryption-icon encryption-e2ee"
            title={$t('dm.e2ee_hint')}
            aria-label={$t('dm.e2ee')}
          >lock</span>
        {:else if conversation.encryption_status === 'at_rest'}
          <span
            class="material-symbols-outlined encryption-icon encryption-at-rest"
            title={$t('dm.at_rest_hint')}
            aria-label={$t('dm.at_rest')}
          >lock</span>
        {:else if conversation.encryption_status === 'federated'}
          <span
            class="material-symbols-outlined encryption-icon encryption-federated"
            title={$t('dm.unencrypted_hint')}
            aria-label={$t('dm.unencrypted')}
          >lock_open</span>
        {/if}
      </span>
      <span class="conversation-time">{timeAgo}</span>
    </div>
    {#if !conversation.accepted}
      <div class="conversation-pending">{$t('dm.message_request')}</div>
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
    min-height: 60px;
  }

  .conversation-item:hover {
    background: var(--color-surface);
  }

  .conversation-item:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: -2px;
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
    font-size: var(--text-base);
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
    font-size: var(--text-sm);
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
    font-size: var(--text-xs);
    font-weight: 700;
    line-height: 1;
    flex-shrink: 0;
  }

  .encryption-icon {
    font-size: 14px;
    vertical-align: middle;
    margin-inline-start: 4px;
  }

  /* Amber: encrypted at rest, server can decrypt. Not full E2E. */
  .encryption-at-rest {
    color: var(--color-warning);
  }

  /* Red + open lock: federated DM, remote server saw plaintext. */
  .encryption-federated {
    color: var(--color-danger);
  }

  /* Reserved for future end-to-end encryption (green = fully private). */
  .encryption-e2ee {
    color: var(--color-success);
  }

  .conversation-pending {
    font-size: var(--text-xs);
    color: var(--color-warning);
    font-weight: 600;
    margin-block-start: 2px;
  }
</style>

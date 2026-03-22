<script lang="ts">
  import type { Message } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';

  let {
    message,
    isOwn = false,
    showAvatar = true
  }: {
    message: Message;
    isOwn?: boolean;
    showAvatar?: boolean;
  } = $props();

  let formattedTime = $derived(
    new Date(message.created_at).toLocaleTimeString(undefined, {
      hour: 'numeric',
      minute: '2-digit'
    })
  );

  let isRead = $derived(!!message.read_at);
  let mediaAttachments = $derived(message.media_attachments || []);
  let sender = $derived(message.sender || {});
</script>

<div class="message-row" class:own={isOwn}>
  {#if !isOwn && showAvatar}
    <div class="message-avatar">
      <Avatar
        src={sender.avatar_url}
        name={sender.display_name || sender.handle || '?'}
        size="sm"
      />
    </div>
  {:else if !isOwn}
    <div class="avatar-spacer"></div>
  {/if}

  <div class="bubble" class:bubble-own={isOwn} class:bubble-other={!isOwn}>
    {#if message.content_html}
      {@html message.content_html}
    {:else}
      <p class="message-text">{message.content}</p>
    {/if}

    {#if mediaAttachments.length > 0}
      <div class="message-media">
        {#each mediaAttachments as attachment (attachment.id)}
          {#if attachment.type === 'image'}
            <img
              src={attachment.preview_url || attachment.url}
              alt={attachment.description || 'Attached image'}
              class="media-image"
              loading="lazy"
            />
          {:else if attachment.type === 'video'}
            <video
              src={attachment.url}
              controls
              preload="metadata"
              class="media-video"
            >
              <track kind="captions" />
            </video>
          {/if}
        {/each}
      </div>
    {/if}

    <div class="message-meta">
      <time class="message-time" datetime={message.created_at}>{formattedTime}</time>
      {#if message.edited_at}
        <span class="message-edited">edited</span>
      {/if}
      {#if isOwn}
        <span class="read-receipt" class:read={isRead} aria-label={isRead ? 'Read' : 'Sent'}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            {#if isRead}
              <polyline points="1 12 5 16 12 9" />
              <polyline points="7 12 11 16 18 9" />
            {:else}
              <polyline points="4 12 8 16 16 8" />
            {/if}
          </svg>
        </span>
      {/if}
    </div>
  </div>
</div>

<style>
  .message-row {
    display: flex;
    align-items: flex-end;
    gap: var(--space-2);
    margin-block-end: var(--space-1);
  }

  .message-row.own {
    flex-direction: row-reverse;
  }

  .message-avatar {
    flex-shrink: 0;
  }

  .avatar-spacer {
    width: 28px;
    flex-shrink: 0;
  }

  .bubble {
    padding: var(--space-2) var(--space-3);
    word-break: break-word;
  }

  .bubble-own {
    background: var(--color-primary-soft);
    border-radius: var(--radius-lg) var(--radius-lg) var(--radius-xs) var(--radius-lg);
    margin-inline-start: auto;
    max-width: 70%;
  }

  .bubble-other {
    background: var(--color-surface);
    border-radius: var(--radius-lg) var(--radius-lg) var(--radius-lg) var(--radius-xs);
    margin-inline-end: auto;
    max-width: 70%;
  }

  .message-text {
    font-size: var(--text-sm);
    line-height: 1.5;
    color: var(--color-text);
  }

  .message-media {
    margin-block-start: var(--space-2);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .media-image {
    border-radius: var(--radius-md);
    max-width: 100%;
    max-height: 300px;
    object-fit: cover;
  }

  .media-video {
    border-radius: var(--radius-md);
    max-width: 100%;
    max-height: 300px;
  }

  .message-meta {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    margin-block-start: var(--space-1);
    justify-content: flex-end;
  }

  .message-time {
    font-size: 11px;
    color: var(--color-text-tertiary);
  }

  .message-edited {
    font-size: 11px;
    color: var(--color-text-tertiary);
    font-style: italic;
  }

  .read-receipt {
    color: var(--color-text-tertiary);
    display: flex;
    align-items: center;
  }

  .read-receipt.read {
    color: var(--color-primary);
  }
</style>

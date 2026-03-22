<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import type { Conversation, Message } from '$lib/api/types.js';
  import { getConversation, getMessages, sendMessage, markConversationRead } from '$lib/api/conversations.js';
  import { currentUser } from '$lib/stores/auth.js';
  import MessageBubble from '$lib/components/dm/MessageBubble.svelte';
  import MessageInput from '$lib/components/dm/MessageInput.svelte';
  import TypingIndicator from '$lib/components/dm/TypingIndicator.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';

  let conversation = $state<Conversation | null>(null);
  let messages = $state<Message[]>([]);
  let loading = $state(true);
  let loadingMore = $state(false);
  let sending = $state(false);
  let cursor = $state<string | null>(null);
  let hasMore = $state(true);
  let messagesEndEl: HTMLDivElement | undefined = $state();
  let typingUser = $state<string | null>(null);

  let userId = $state('');
  currentUser.subscribe((u) => {
    userId = u?.id ?? '';
  });

  let conversationId = $derived(page.params.id);

  let otherParticipants = $derived(
    conversation?.participants.filter((p) => p.id !== userId) ?? []
  );

  let displayName = $derived(
    otherParticipants.map((p) => p.display_name || p.handle).join(', ') || 'Conversation'
  );

  let avatarUser = $derived(otherParticipants[0] ?? null);

  onMount(async () => {
    try {
      const [conv, msgResult] = await Promise.all([
        getConversation(conversationId),
        getMessages(conversationId)
      ]);
      conversation = conv;
      messages = msgResult.data.reverse();
      cursor = msgResult.next_cursor;
      hasMore = !!msgResult.next_cursor;
      await markConversationRead(conversationId);
      scrollToBottom();
    } catch {
      // Error loading conversation
    } finally {
      loading = false;
    }
  });

  async function loadMore() {
    if (!cursor || !hasMore || loadingMore) return;
    loadingMore = true;
    try {
      const result = await getMessages(conversationId, cursor);
      messages = [...result.data.reverse(), ...messages];
      cursor = result.next_cursor;
      hasMore = !!result.next_cursor;
    } catch {
      // Error loading more
    } finally {
      loadingMore = false;
    }
  }

  async function handleSend(content: string) {
    if (sending) return;
    sending = true;
    try {
      const msg = await sendMessage(conversationId, { content });
      messages = [...messages, msg];
      scrollToBottom();
    } catch {
      // Error sending
    } finally {
      sending = false;
    }
  }

  function scrollToBottom() {
    requestAnimationFrame(() => {
      messagesEndEl?.scrollIntoView({ behavior: 'smooth' });
    });
  }

  function goBack() {
    goto('/messages');
  }

  function shouldShowAvatar(index: number): boolean {
    if (index === messages.length - 1) return true;
    return messages[index].sender.id !== messages[index + 1].sender.id;
  }
</script>

<svelte:head>
  <title>{displayName} - Messages - HybridSocial</title>
</svelte:head>

<div class="conversation-detail">
  <div class="detail-header">
    <button type="button" class="back-btn" onclick={goBack} aria-label="Back to messages">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="15 18 9 12 15 6" />
      </svg>
    </button>
    {#if avatarUser}
      <Avatar src={avatarUser.avatar_url} name={avatarUser.display_name || avatarUser.handle} size="sm" />
    {/if}
    <h1 class="detail-title">{displayName}</h1>
  </div>

  {#if loading}
    <div class="detail-loading">
      <Spinner />
    </div>
  {:else}
    <div class="messages-container" role="log" aria-label="Messages">
      {#if hasMore && messages.length > 0}
        <button type="button" class="load-more-btn" onclick={loadMore} disabled={loadingMore}>
          {loadingMore ? 'Loading...' : 'Load older messages'}
        </button>
      {/if}

      {#each messages as message, i (message.id)}
        <MessageBubble
          {message}
          isOwn={message.sender.id === userId}
          showAvatar={shouldShowAvatar(i)}
        />
      {/each}

      {#if typingUser}
        <TypingIndicator name={typingUser} />
      {/if}

      <div bind:this={messagesEndEl} class="messages-end" aria-hidden="true"></div>
    </div>

    <MessageInput onsend={handleSend} disabled={sending} />
  {/if}
</div>

<style>
  .conversation-detail {
    display: flex;
    flex-direction: column;
    height: calc(100vh - var(--header-height));
    margin: calc(-1 * var(--space-4));
    overflow: hidden;
  }

  .detail-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-block-end: 1px solid var(--color-border);
    flex-shrink: 0;
  }

  .back-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border: none;
    background: none;
    border-radius: var(--radius-full);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .back-btn:hover {
    background: var(--color-surface);
  }

  .detail-title {
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .detail-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 1;
  }

  .messages-container {
    flex: 1;
    overflow-y: auto;
    padding: var(--space-4);
    display: flex;
    flex-direction: column;
  }

  .load-more-btn {
    align-self: center;
    padding: var(--space-2) var(--space-4);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    background: var(--color-surface);
    color: var(--color-text-secondary);
    font-size: var(--text-xs);
    cursor: pointer;
    transition: background var(--transition-fast);
    margin-block-end: var(--space-4);
  }

  .load-more-btn:hover:not(:disabled) {
    background: var(--color-surface-raised);
  }

  .load-more-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .messages-end {
    height: 1px;
  }

  /* Desktop: hide back button since split view is available */
  @media (min-width: 769px) {
    .back-btn {
      display: none;
    }
  }
</style>

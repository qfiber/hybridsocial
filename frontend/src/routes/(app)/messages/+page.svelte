<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { get } from 'svelte/store';
  import type { Conversation, Message } from '$lib/api/types.js';
  import { getConversations, getMessages, sendMessage, markConversationRead } from '$lib/api/conversations.js';
  import { currentUser } from '$lib/stores/auth.js';
  import ConversationItem from '$lib/components/dm/ConversationItem.svelte';
  import MessageBubble from '$lib/components/dm/MessageBubble.svelte';
  import MessageInput from '$lib/components/dm/MessageInput.svelte';
  import TypingIndicator from '$lib/components/dm/TypingIndicator.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let conversations = $state<Conversation[]>([]);
  let selectedId = $state<string | null>(null);
  let messages = $state<Message[]>([]);
  let loading = $state(true);
  let loadingMessages = $state(false);
  let sending = $state(false);
  let conversationsCursor = $state<string | null>(null);
  let messagesCursor = $state<string | null>(null);
  let hasMoreConversations = $state(true);
  let hasMoreMessages = $state(true);
  let messagesEndEl: HTMLDivElement | undefined = $state();
  let messagesContainerEl: HTMLDivElement | undefined = $state();

  let userId = $state('');
  currentUser.subscribe((u) => {
    userId = u?.id ?? '';
  });

  let selectedConversation = $derived(
    conversations.find((c) => c.id === selectedId) ?? null
  );

  let typingUser = $state<string | null>(null);

  onMount(async () => {
    try {
      const result = await getConversations();
      conversations = Array.isArray(result) ? result : (result as any).data || [];
      conversationsCursor = Array.isArray(result) ? null : (result as any).next_cursor;
      hasMoreConversations = conversations.length >= 20;
    } catch {
      // Error loading conversations
    } finally {
      loading = false;
    }
  });

  async function selectConversation(id: string) {
    if (selectedId === id) return;
    selectedId = id;
    messages = [];
    loadingMessages = true;
    messagesCursor = null;
    hasMoreMessages = true;

    try {
      const result = await getMessages(id);
      const data = Array.isArray(result) ? result : (result as any).data || [];
      messages = [...data].reverse();
      messagesCursor = data.length > 0 ? data[data.length - 1]?.id : null;
      hasMoreMessages = data.length >= 20;
      await markConversationRead(id);
      // Update unread count locally
      conversations = conversations.map((c) =>
        c.id === id ? { ...c, unread_count: 0 } : c
      );
      scrollToBottom();
    } catch {
      // Error loading messages
    } finally {
      loadingMessages = false;
    }
  }

  async function loadMoreMessages() {
    if (!selectedId || !messagesCursor || !hasMoreMessages || loadingMessages) return;
    loadingMessages = true;
    try {
      const result = await getMessages(selectedId, messagesCursor);
      messages = [...result.data.reverse(), ...messages];
      messagesCursor = result.next_cursor;
      hasMoreMessages = !!result.next_cursor;
    } catch {
      // Error loading more messages
    } finally {
      loadingMessages = false;
    }
  }

  async function handleSend(content: string) {
    if (!selectedId || sending) return;
    sending = true;
    try {
      const msg = await sendMessage(selectedId, { content });
      messages = [...messages, msg];
      // Update conversation list with latest message
      conversations = conversations.map((c) =>
        c.id === selectedId
          ? { ...c, last_message: msg, updated_at: msg.created_at }
          : c
      );
      // Re-sort conversations by last message
      conversations = [...conversations].sort(
        (a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()
      );
      scrollToBottom();
    } catch {
      // Error sending message
    } finally {
      sending = false;
    }
  }

  function scrollToBottom() {
    requestAnimationFrame(() => {
      messagesEndEl?.scrollIntoView({ behavior: 'smooth' });
    });
  }

  function handleNewConversation() {
    goto('/messages/new');
  }

  function handleMobileSelect(id: string) {
    goto(`/messages/${id}`);
  }

  // Group consecutive messages from same sender for avatar display
  function shouldShowAvatar(index: number): boolean {
    if (index === messages.length - 1) return true;
    return messages[index].sender.id !== messages[index + 1].sender.id;
  }
</script>

<svelte:head>
  <title>Messages - HybridSocial</title>
</svelte:head>

<div class="messages-page">
  <!-- Conversation list panel -->
  <div class="conversations-panel" class:has-selection={!!selectedId}>
    <div class="panel-header">
      <h1 class="panel-title">Messages</h1>
      <button type="button" class="btn btn-primary btn-sm" onclick={handleNewConversation}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z" />
          <line x1="12" y1="8" x2="12" y2="14" />
          <line x1="9" y1="11" x2="15" y2="11" />
        </svg>
        New
      </button>
    </div>

    {#if loading}
      <div class="panel-loading">
        <Spinner />
      </div>
    {:else if conversations.length === 0}
      <div class="panel-empty">
        <p class="empty-text">No conversations yet</p>
        <p class="empty-hint">Start a new conversation to message someone.</p>
      </div>
    {:else}
      <div class="conversation-list" role="listbox" aria-label="Conversations">
        {#each conversations as conversation (conversation.id)}
          <!-- Desktop: select in-page, Mobile: navigate -->
          <div class="conversation-desktop">
            <ConversationItem
              {conversation}
              active={selectedId === conversation.id}
              currentUserId={userId}
              onclick={() => selectConversation(conversation.id)}
            />
          </div>
          <div class="conversation-mobile">
            <ConversationItem
              {conversation}
              currentUserId={userId}
              onclick={() => handleMobileSelect(conversation.id)}
            />
          </div>
        {/each}
      </div>
    {/if}
  </div>

  <!-- Messages panel (desktop) -->
  <div class="messages-panel" class:empty={!selectedId}>
    {#if !selectedId}
      <div class="no-selection">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--color-text-tertiary)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z" />
        </svg>
        <p class="no-selection-text">Select a conversation</p>
        <p class="no-selection-hint">Choose a conversation from the list to start messaging.</p>
      </div>
    {:else}
      <div class="messages-header">
        <h2 class="messages-title">
          {selectedConversation?.participants
            .filter((p) => p.id !== userId)
            .map((p) => p.display_name || p.handle)
            .join(', ') ?? 'Conversation'}
        </h2>
      </div>

      <div
        class="messages-container"
        bind:this={messagesContainerEl}
        role="log"
        aria-label="Messages"
      >
        {#if hasMoreMessages && messages.length > 0}
          <button type="button" class="load-more-btn" onclick={loadMoreMessages} disabled={loadingMessages}>
            {loadingMessages ? 'Loading...' : 'Load older messages'}
          </button>
        {/if}

        {#if loadingMessages && messages.length === 0}
          <div class="messages-loading">
            <Spinner />
          </div>
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
</div>

<style>
  .messages-page {
    display: grid;
    grid-template-columns: 340px 1fr;
    height: calc(100vh - var(--header-height));
    margin: calc(-1 * var(--space-4));
    overflow: hidden;
  }

  .conversations-panel {
    border-inline-end: 1px solid var(--color-border);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .panel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-4);
    border-block-end: 1px solid var(--color-border);
    flex-shrink: 0;
  }

  .panel-title {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
  }

  .panel-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-8);
  }

  .panel-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: var(--space-8);
    gap: var(--space-2);
    flex: 1;
  }

  .empty-text {
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--color-text);
  }

  .empty-hint {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    text-align: center;
  }

  .conversation-list {
    flex: 1;
    overflow-y: auto;
    padding: var(--space-2);
  }

  .conversation-desktop {
    display: block;
  }

  .conversation-mobile {
    display: none;
  }

  .messages-panel {
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .messages-panel.empty {
    align-items: center;
    justify-content: center;
  }

  .no-selection {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-8);
  }

  .no-selection-text {
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--color-text-secondary);
  }

  .no-selection-hint {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .messages-header {
    display: flex;
    align-items: center;
    padding: var(--space-3) var(--space-4);
    border-block-end: 1px solid var(--color-border);
    flex-shrink: 0;
  }

  .messages-title {
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--color-text);
  }

  .messages-container {
    flex: 1;
    overflow-y: auto;
    padding: var(--space-4);
    display: flex;
    flex-direction: column;
  }

  .messages-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-8);
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

  /* Mobile: show only conversation list or detail */
  @media (max-width: 768px) {
    .messages-page {
      grid-template-columns: 1fr;
    }

    .messages-panel {
      display: none;
    }

    .conversations-panel.has-selection {
      display: flex;
    }

    .conversation-desktop {
      display: none;
    }

    .conversation-mobile {
      display: block;
    }
  }
</style>

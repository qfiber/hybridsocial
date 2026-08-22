<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import type { Conversation, Message } from '$lib/api/types.js';
  import {
    getConversation,
    getMessages,
    sendMessage,
    markConversationRead,
    sendTyping,
    deleteConversation,
    deleteMessage as apiDeleteMessage,
    addMessageReaction,
    editMessage as apiEditMessage,
  } from '$lib/api/conversations.js';
  import { markConversationReadLocal } from '$lib/stores/dm-unread.js';
  import { currentUser } from '$lib/stores/auth.js';
  import MessageBubble from '$lib/components/dm/MessageBubble.svelte';
  import MessageInput from '$lib/components/dm/MessageInput.svelte';
  import TypingIndicator from '$lib/components/dm/TypingIndicator.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import ParticipantStrip from '$lib/components/dm/ParticipantStrip.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { slide } from 'svelte/transition';
  import { cubicOut } from 'svelte/easing';
  import { instanceName } from '$lib/stores/instance.js';

  let conversation = $state<Conversation | null>(null);
  let messages = $state<Message[]>([]);
  let loading = $state(true);
  let loadingMore = $state(false);
  let cursor = $state<string | null>(null);
  let hasMore = $state(true);
  let messagesEndEl: HTMLDivElement | undefined = $state();
  let scrollEl: HTMLDivElement | undefined = $state();
  let typingUser = $state<string | null>(null);
  let typingTimer: ReturnType<typeof setTimeout> | null = null;

  // Fire-and-forget typing ping (the composer throttles the calls).
  function handleTyping() {
    const cid = page.params.id;
    if (cid) sendTyping(cid).catch(() => {});
  }
  // The message the user is currently composing a reply to. Cleared on
  // send / cancel / conversation switch. The composer renders a quoted
  // preview while this is non-null and includes reply_to_id in the
  // send payload.
  let replyingTo = $state<Message | null>(null);

  // O(1) lookup for rendering quoted previews on incoming bubbles
  // that have a non-null reply_to_id. Recomputes from the messages
  // array whenever it changes.
  let messagesById = $derived(new Map(messages.map((m) => [m.id, m])));

  let userId = $state('');
  currentUser.subscribe((u) => {
    userId = u?.id ?? '';
  });

  let conversationId = $derived(page.params.id!);

  let otherParticipants = $derived(
    // `id` is the conversation_participant row uuid; the viewer's
    // identity matches `identity_id`. See ConversationParticipant in
    // types.ts.
    conversation?.participants.filter((p) => p.identity_id !== userId) ?? []
  );

  let displayName = $derived(
    otherParticipants.map((p) => p.display_name || p.handle).join(', ') || 'Conversation'
  );

  let avatarUser = $derived(otherParticipants[0] ?? null);

  // SvelteKit reuses this component when navigating between conversations
  // (only the `[id]` param changes), so `onMount` never re-fires and the
  // old messages would remain on screen. Keyed on `conversationId`, the
  // effect reloads whenever the URL points to a new thread, and a token
  // lets us ignore stale responses if the user clicks another convo before
  // the previous fetch resolves.
  let loadToken = 0;

  $effect(() => {
    const cid = conversationId;
    if (!cid) return;
    const token = ++loadToken;

    // Reset per-conversation state up front so the UI doesn't flash the
    // previous chat's messages while the new one is loading.
    conversation = null;
    messages = [];
    cursor = null;
    hasMore = true;
    loading = true;
    replyingTo = null;

    void (async () => {
      try {
        const [conv, msgResult] = await Promise.all([
          getConversation(cid),
          getMessages(cid)
        ]);
        if (token !== loadToken) return;
        conversation = conv;
        messages = msgResult.data.reverse();
        cursor = msgResult.next_cursor;
        hasMore = !!msgResult.next_cursor;
        markConversationReadLocal(cid);
        await markConversationRead(cid);
        if (token !== loadToken) return;
        scrollToBottom(true);
      } catch (err) {
        if (token !== loadToken) return;
        console.error('[messages] load failed', err);
        addToast('Could not load this conversation', 'error');
      } finally {
        if (token === loadToken) loading = false;
      }
    })();
  });

  onMount(() => {
    window.addEventListener('chat-event', handleChatEvent as EventListener);
    return () => {
      window.removeEventListener('chat-event', handleChatEvent as EventListener);
    };
  });

  function handleChatEvent(ev: Event) {
    const detail = (ev as CustomEvent<{ type: string; data: Record<string, unknown> }>).detail;
    if (!detail) return;

    const data = detail.data;
    if (data?.conversation_id !== conversationId) return;

    switch (detail.type) {
      case 'chat.new_message':
        appendLiveMessage(data as unknown as Message);
        // Their message landed — they've stopped typing.
        typingUser = null;
        break;
      case 'chat.typing': {
        const { identity_id, conversation_id } = data as {
          identity_id?: string;
          conversation_id?: string;
        };
        // Ignore our own echo and pings for other conversations (the
        // user stream carries every conversation the viewer is in).
        if (!identity_id || identity_id === userId) break;
        if (conversation_id && conversation_id !== page.params.id) break;
        const who = conversation?.participants.find((p) => p.identity_id === identity_id);
        typingUser = who?.display_name || who?.handle || 'Someone';
        if (typingTimer) clearTimeout(typingTimer);
        typingTimer = setTimeout(() => {
          typingUser = null;
        }, 4000);
        break;
      }
      case 'chat.delivered': {
        const { message_id, status } = data as { message_id: string; status?: string };
        if (!message_id) break;
        // Only the sender cares about the tick flip; recipient bubbles
        // don't render delivery_status. We still update everyone's
        // local copy uniformly — the bubble decides what to show.
        messages = messages.map((m) =>
          m.id === message_id
            ? { ...m, delivery_status: (status || 'delivered') as Message['delivery_status'] }
            : m,
        );
        break;
      }
      case 'chat.read': {
        // The other participant just opened the conversation. Bump
        // every one of MY sent messages up to (and including) their
        // last_read_message_id to 'read' so the ticks colour. The
        // backend already persisted the state change; this just keeps
        // the UI in sync without a refetch.
        const { identity_id, last_read_message_id } = data as {
          identity_id: string;
          last_read_message_id?: string;
        };
        if (!last_read_message_id || identity_id === userId) break;
        const cutoffIdx = messages.findIndex((m) => m.id === last_read_message_id);
        if (cutoffIdx === -1) break;
        const cutoffAt = new Date(messages[cutoffIdx].created_at).getTime();
        messages = messages.map((m) => {
          if (m.sender.id !== userId) return m;
          const at = new Date(m.created_at).getTime();
          if (at <= cutoffAt) return { ...m, delivery_status: 'read' };
          return m;
        });
        break;
      }
      case 'chat.reaction_added':
      case 'chat.reaction_removed':
        applyReactionDelta(data as { message_id: string; reactions?: Message['reactions'] });
        break;
    }
  }

  function appendLiveMessage(incoming: Message) {
    // Outbound echoes: the user already sees their own bubble from the
    // optimistic `handleSend` append, so skip duplicates keyed by id.
    if (messages.some((m) => m.id === incoming.id)) return;
    messages = [...messages, incoming];
    scrollToBottom();
    // Eagerly mark read so the badge doesn't linger while the tab is focused.
    if (incoming.sender.id !== userId) {
      void markConversationRead(conversationId);
    }
  }

  function applyReactionDelta({
    message_id,
    reactions,
  }: {
    message_id: string;
    reactions?: Message['reactions'];
  }) {
    if (!reactions) return;
    messages = messages.map((m) => (m.id === message_id ? { ...m, reactions } : m));
  }

  async function loadMore() {
    if (!cursor || !hasMore || loadingMore) return;
    loadingMore = true;
    // Anchor the viewport: prepending older messages grows the scroll
    // height above the current view, so restore scrollTop by the delta
    // to keep the user's place instead of snapping to the top.
    const prevHeight = scrollEl?.scrollHeight ?? 0;
    const prevTop = scrollEl?.scrollTop ?? 0;
    try {
      const result = await getMessages(conversationId, cursor);
      messages = [...result.data.reverse(), ...messages];
      cursor = result.next_cursor;
      hasMore = !!result.next_cursor;
      await tick();
      if (scrollEl) {
        scrollEl.scrollTop = prevTop + (scrollEl.scrollHeight - prevHeight);
      }
    } catch {
      // Error loading more
    } finally {
      loadingMore = false;
    }
  }

  // Auto-load older history as the user scrolls near the top.
  function handleScroll() {
    if (scrollEl && scrollEl.scrollTop < 120 && hasMore && !loadingMore) {
      void loadMore();
    }
  }

  // The composer stays interactive at all times. MessageInput clears
  // its textarea the moment it fires onsend, so the user can't
  // accidentally double-send the same content — and they SHOULD be
  // allowed to queue the next message while the previous is in flight.
  // The previous "disabled while sending" pattern had a sticky bug
  // that left the input frozen until a page refresh; simpler to keep
  // it live and let the async sends resolve independently.
  async function handleSend(
    content: string,
    mediaIds: string[] = [],
    replyToId: string | null = null,
  ) {
    // Snapshot the reply target so a late-resolving send can't clobber
    // the user's next "fresh" message with a stale reply chip.
    replyingTo = null;
    try {
      const msg = await sendMessage(conversationId, {
        content,
        ...(mediaIds.length > 0 ? { media_ids: mediaIds } : {}),
        ...(replyToId ? { reply_to_id: replyToId } : {}),
      });
      // The SSE stream broadcasts our own message back to us, and the
      // POST response can race with it either direction. If we blindly
      // append both, {#each messages as m (m.id)} throws
      // `each_key_duplicate`, which poisons Svelte's render loop and
      // makes the composer look frozen until the user refreshes.
      // Dedup by id so only the first arrival wins.
      if (!messages.some((m) => m.id === msg.id)) {
        messages = [...messages, msg];
      }
      triggerRipple();
      scrollToBottom();
    } catch (err) {
      console.error('[messages] send failed', err);
      addToast('Could not send message. Please try again.', 'error');
    }
  }

  function scrollToBottom(instant = false) {
    requestAnimationFrame(() => {
      messagesEndEl?.scrollIntoView({ behavior: instant ? 'auto' : 'smooth' });
    });
  }

  // Day separators — group the thread by calendar day so a long
  // conversation reads as a timeline instead of one undivided column.
  function dayLabel(iso: string): string {
    const d = new Date(iso);
    const now = new Date();
    const startOf = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
    const days = Math.round((startOf(now) - startOf(d)) / 86_400_000);
    if (days === 0) return 'Today';
    if (days === 1) return 'Yesterday';
    return d.toLocaleDateString(undefined, {
      weekday: 'long',
      month: 'short',
      day: 'numeric',
      year: d.getFullYear() === now.getFullYear() ? undefined : 'numeric',
    });
  }

  function isNewDay(i: number): boolean {
    if (i === 0) return true;
    return (
      new Date(messages[i].created_at).toDateString() !==
      new Date(messages[i - 1].created_at).toDateString()
    );
  }

  function scrollToMessage(messageId: string) {
    // The bubble's `data-message-id` is set on its outer slot below.
    // We only scroll if the original is loaded into the DOM (it might
    // be paged out above the cursor); otherwise the tap is a no-op.
    const el = document.querySelector(
      `[data-message-id="${CSS.escape(messageId)}"]`,
    );
    if (el instanceof HTMLElement) {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      el.classList.add('bubble-slot-highlight');
      setTimeout(() => el.classList.remove('bubble-slot-highlight'), 1500);
    }
  }

  // Toggled true for ~600ms after a new bubble is appended; bubbles
  // read this via :global(.messages-container.rippling) and run a
  // brief, staggered upward bounce.
  let rippling = $state(false);
  let rippleTimer: ReturnType<typeof setTimeout> | null = null;

  function triggerRipple() {
    rippling = true;
    if (rippleTimer) clearTimeout(rippleTimer);
    rippleTimer = setTimeout(() => {
      rippling = false;
    }, 600);
  }

  function goBack() {
    goto('/messages');
  }

  let confirmingDeleteConv = $state(false);
  let deletingConv = $state(false);

  async function handleDeleteConversation() {
    if (deletingConv) return;
    deletingConv = true;
    try {
      await deleteConversation(conversationId);
      // Let the layout drop this row from the sidebar immediately
      // — the backend doesn't (yet) broadcast conversation-level
      // deletes, and a full refetch on navigate would flicker.
      window.dispatchEvent(
        new CustomEvent('conversation-deleted', { detail: { id: conversationId } }),
      );
      addToast('Conversation deleted', 'success');
      goto('/messages');
    } catch {
      addToast('Failed to delete conversation', 'error');
      deletingConv = false;
      confirmingDeleteConv = false;
    }
  }

  async function handleDeleteMessage(messageId: string) {
    try {
      await apiDeleteMessage(conversationId, messageId);
      messages = messages.filter((m) => m.id !== messageId);
    } catch {
      addToast('Failed to delete message', 'error');
    }
  }

  async function handleEditMessage(messageId: string, content: string) {
    try {
      const updated = await apiEditMessage(conversationId, messageId, content);
      messages = messages.map((m) => (m.id === messageId ? { ...m, ...updated } : m));
    } catch (e: unknown) {
      const err = e as { body?: { error?: string; message?: string } };
      if (err?.body?.error === 'message.edit_window_expired') {
        addToast(err.body.message || 'Edit window has closed', 'error');
      } else {
        addToast('Failed to edit message', 'error');
      }
      throw e;
    }
  }

  async function handleReactMessage(messageId: string, emoji: string) {
    try {
      // Backend enforces one-per-user-per-message. Response tells us
      // whether this was "added" (first reaction), "removed" (same
      // emoji toggled off), or "swapped" (replaced a previous emoji).
      // We apply the returned aggregate to the local state so the
      // count + account list match exactly what other participants
      // will see via SSE.
      const res = await addMessageReaction(conversationId, messageId, emoji);
      const nextReactions = res.reactions ?? [];
      messages = messages.map((m) =>
        m.id === messageId ? { ...m, reactions: nextReactions } : m
      );
    } catch (e: unknown) {
      const err = e as { body?: { error?: string; message?: string } };
      if (err?.body?.error === 'reaction.premium_required') {
        addToast(err.body.message || 'That reaction needs a premium tier', 'error');
      } else {
        addToast('Failed to react', 'error');
      }
    }
  }

  function shouldShowAvatar(index: number): boolean {
    if (index === messages.length - 1) return true;
    return messages[index].sender.id !== messages[index + 1].sender.id;
  }
</script>

<svelte:head>
  <title>{displayName} - Messages - {$instanceName}</title>
</svelte:head>

<div class="conversation-detail">
  <div class="detail-header">
    <button type="button" class="back-btn" onclick={goBack} aria-label="Back to messages">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="15 18 9 12 15 6" />
      </svg>
    </button>

    <div class="detail-header-strip">
      <ParticipantStrip participants={otherParticipants} />
    </div>

    <div class="detail-header-meta">
      {#if conversation?.encryption_status === 'e2ee'}
        <span
          class="material-symbols-outlined header-encryption header-e2ee"
          title="End-to-end encrypted. Only participants can read."
          aria-label="End-to-end encrypted"
        >lock</span>
      {:else if conversation?.encryption_status === 'at_rest'}
        <span
          class="material-symbols-outlined header-encryption header-at-rest"
          title="Encrypted on disk. This is not end-to-end ecnryption"
          aria-label="Encrypted at rest"
        >lock</span>
      {:else if conversation?.encryption_status === 'federated'}
        <span
          class="material-symbols-outlined header-encryption header-federated"
          title="Not encrypted. DMs with remote users are not private/encrypted"
          aria-label="Not encrypted (federated)"
        >lock_open</span>
      {/if}
    </div>

    <div class="detail-header-actions">
      <button
        type="button"
        class="header-action header-action-danger"
        onclick={() => (confirmingDeleteConv = true)}
        title="Delete conversation"
        aria-label="Delete conversation"
      >
        <span class="material-symbols-outlined">delete</span>
        <span class="header-action-label">Delete</span>
      </button>
    </div>
  </div>

  {#if confirmingDeleteConv}
    <div
      class="confirm-banner"
      role="alertdialog"
      aria-live="polite"
      transition:slide={{ duration: 200, easing: cubicOut }}
    >
      <span>
        Delete this conversation from your inbox? The other person
        keeps their copy. You can't undo this for yourself.
      </span>
      <div class="confirm-actions">
        <button
          type="button"
          class="btn btn-ghost"
          onclick={() => (confirmingDeleteConv = false)}
          disabled={deletingConv}
        >
          Cancel
        </button>
        <button
          type="button"
          class="btn btn-danger"
          onclick={handleDeleteConversation}
          disabled={deletingConv}
        >
          {deletingConv ? 'Deleting…' : 'Delete'}
        </button>
      </div>
    </div>
  {/if}

  {#if loading}
    <div class="detail-loading">
      <Spinner />
    </div>
  {:else}
    <div class="messages-container" class:rippling role="log" aria-label="Messages" bind:this={scrollEl} onscroll={handleScroll}>
      {#if hasMore && messages.length > 0}
        <button type="button" class="load-more-btn" onclick={loadMore} disabled={loadingMore}>
          {loadingMore ? 'Loading...' : 'Load older messages'}
        </button>
      {/if}

      {#if messages.length === 0}
        <div class="thread-empty">
          <div class="thread-empty-icon" aria-hidden="true">
            <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
            </svg>
          </div>
          <p class="thread-empty-title">No messages yet</p>
          <p class="thread-empty-text">Say hello — send the first message below.</p>
        </div>
      {/if}

      {#each messages as message, i (message.id)}
        {#if isNewDay(i)}
          <div class="day-sep" role="separator">
            <span class="day-sep-label">{dayLabel(message.created_at)}</span>
          </div>
        {/if}
        <div
          class="bubble-slot"
          data-message-id={message.id}
          style="--ripple-i: {messages.length - 1 - i}"
        >
          <MessageBubble
            {message}
            {conversationId}
            isOwn={message.sender.id === userId}
            showAvatar={shouldShowAvatar(i)}
            replyTo={message.reply_to_id ? messagesById.get(message.reply_to_id) ?? null : null}
            ondelete={handleDeleteMessage}
            onreact={handleReactMessage}
            onedit={handleEditMessage}
            onreply={(m) => { replyingTo = m; }}
            onreplyclick={scrollToMessage}
          />
        </div>
      {/each}

      {#if typingUser}
        <TypingIndicator name={typingUser} />
      {/if}

      <div bind:this={messagesEndEl} class="messages-end" aria-hidden="true"></div>
    </div>

    <MessageInput
      onsend={handleSend}
      {replyingTo}
      oncancelreply={() => (replyingTo = null)}
      ontyping={handleTyping}
    />
  {/if}
</div>

<style>
  .conversation-detail {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    overflow: hidden;
  }

  .bubble-slot {
    transition: background var(--transition-fast);
    border-radius: var(--radius-md);
  }

  /* Brief tinted flash on the bubble that a reply-quote click jumps
     to — gives the user a clear "this is the message" anchor. */
  :global(.bubble-slot-highlight) {
    background: var(--color-primary-soft);
  }

  .detail-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-block-end: 1px solid var(--color-border);
    flex-shrink: 0;
  }

  .detail-header-strip {
    flex: 1;
    min-width: 0;
  }

  .detail-header-meta {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    flex-shrink: 0;
  }

  .detail-header-actions {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .header-action {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 12px;
    background: transparent;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text-secondary);
    cursor: pointer;
    transition:
      background-color var(--transition-fast),
      color var(--transition-fast),
      border-color var(--transition-fast),
      transform var(--transition-fast);
  }

  .header-action:active {
    transform: scale(0.96);
  }

  .header-action:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .header-action .material-symbols-outlined {
    font-size: 18px !important;
  }

  .header-action-danger:hover {
    color: var(--color-danger, #b00);
    border-color: var(--color-danger, #b00);
    background: var(--color-danger-surface, rgba(176, 0, 0, 0.06));
  }

  /* Hide the text label on narrow viewports — icon alone is enough. */
  @media (max-width: 480px) {
    .header-action-label {
      display: none;
    }
  }

  .confirm-banner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    background: var(--color-warning-surface, rgba(217, 119, 6, 0.08));
    border-block-end: 1px solid var(--color-warning, #d97706);
    font-size: var(--text-sm);
  }

  .confirm-actions {
    display: flex;
    gap: var(--space-2);
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


  .header-encryption {
    font-size: 16px;
  }

  .header-at-rest {
    color: var(--color-warning, #d97706);
  }

  .header-federated {
    color: var(--color-danger, #dc2626);
  }

  .header-e2ee {
    color: var(--color-success, #16a34a);
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

  /* Day separator — a centred pill labelling each calendar day. */
  .day-sep {
    display: flex;
    justify-content: center;
    margin-block: var(--space-3);
  }

  .day-sep-label {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    background: var(--color-surface-container);
    padding: 3px var(--space-3);
    border-radius: var(--radius-full);
  }

  /* Empty thread (new conversation). */
  .thread-empty {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    gap: var(--space-1);
    padding: var(--space-8) var(--space-4);
  }

  .thread-empty-icon {
    width: 64px;
    height: 64px;
    border-radius: var(--radius-full);
    display: grid;
    place-items: center;
    color: var(--color-primary);
    background: var(--color-secondary-container);
    margin-block-end: var(--space-3);
  }

  .thread-empty-title {
    font-size: var(--text-base);
    font-weight: 700;
    color: var(--color-text);
  }

  .thread-empty-text {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  /* Desktop: hide back button since split view is available */
  @media (min-width: 769px) {
    .back-btn {
      display: none;
    }
  }

</style>

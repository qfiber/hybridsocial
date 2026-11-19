<script lang="ts">
  import { t } from '$lib/stores/i18n.js';
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import type { Conversation } from '$lib/api/types.js';
  import { getConversations } from '$lib/api/conversations.js';
  import { currentUser } from '$lib/stores/auth.js';
  import ConversationItem from '$lib/components/dm/ConversationItem.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let { children } = $props();

  let conversations = $state<Conversation[]>([]);
  let loading = $state(true);

  let userId = $state('');
  currentUser.subscribe((u) => {
    userId = u?.id ?? '';
  });

  let selectedId = $derived(page.params.id ?? null);
  // `hasSelection` drives the mobile panel-swap CSS. Treat `/messages/new`
  // as a selection too — it renders inside `content-panel`, and without
  // this it stayed hidden on mobile so the new-conversation search UI
  // was unreachable.
  let hasSelection = $derived(
    !!selectedId || page.url.pathname.startsWith('/messages/new')
  );

  // When the URL points at a conversation that isn't in the sidebar
  // yet — typically right after /messages/new creates one, before
  // any message has been sent — pull the updated list so the new
  // thread surfaces without a full page reload.
  $effect(() => {
    if (!selectedId || loading) return;
    if (!conversations.some((c) => c.id === selectedId)) {
      void refreshConversations();
    }
  });

  onMount(() => {
    void (async () => {
      try {
        const result = await getConversations();
        conversations = Array.isArray(result)
          ? result
          : ((result as unknown) as { data?: Conversation[] }).data ?? [];
      } catch {
        // Error loading conversations — surface via toast elsewhere if needed.
      } finally {
        loading = false;
      }
    })();

    window.addEventListener('chat-event', handleChatEvent as EventListener);
    window.addEventListener('conversation-deleted', handleConversationDeleted as EventListener);
    return () => {
      window.removeEventListener('chat-event', handleChatEvent as EventListener);
      window.removeEventListener(
        'conversation-deleted',
        handleConversationDeleted as EventListener,
      );
    };
  });

  function handleChatEvent(ev: Event) {
    const detail = (ev as CustomEvent<{
      type: string;
      data: Record<string, unknown>;
    }>).detail;
    if (!detail) return;

    switch (detail.type) {
      case 'chat.new_message':
        applyNewMessage(detail.data);
        break;
      case 'chat.read':
        applyRead(detail.data);
        break;
    }
  }

  function applyNewMessage(raw: Record<string, unknown>) {
    const msg = raw as {
      id: string;
      conversation_id: string;
      content: string;
      content_type: string;
      sender?: { id: string };
      created_at: string;
    };

    const idx = conversations.findIndex((c) => c.id === msg.conversation_id);
    if (idx === -1) {
      // The stream fired for a conversation we haven't loaded yet —
      // fetch the full list so the new one surfaces in the sidebar.
      refreshConversations();
      return;
    }

    const current = conversations[idx];
    const incrementUnread =
      msg.sender?.id !== userId && selectedId !== msg.conversation_id;

    const updated: Conversation = {
      ...current,
      last_message: {
        id: msg.id,
        content: msg.content,
        content_type: msg.content_type,
        sender_id: msg.sender?.id ?? '',
        created_at: msg.created_at,
      } as unknown as Conversation['last_message'],
      updated_at: msg.created_at,
      unread_count: incrementUnread ? (current.unread_count ?? 0) + 1 : current.unread_count,
    };

    const without = conversations.filter((c) => c.id !== msg.conversation_id);
    conversations = [updated, ...without];
  }

  function applyRead(raw: Record<string, unknown>) {
    const payload = raw as { conversation_id: string; identity_id?: string };
    // Only clear the unread badge when the viewer themselves read it
    // — otherwise the other participant reading their side would
    // wipe our unread state.
    if (payload.identity_id && payload.identity_id !== userId) return;

    conversations = conversations.map((c) =>
      c.id === payload.conversation_id ? { ...c, unread_count: 0 } : c,
    );
  }

  function handleConversationDeleted(ev: Event) {
    const detail = (ev as CustomEvent<{ id: string }>).detail;
    if (!detail?.id) return;
    conversations = conversations.filter((c) => c.id !== detail.id);
  }

  async function refreshConversations() {
    try {
      const result = await getConversations();
      conversations = Array.isArray(result)
        ? result
        : ((result as unknown) as { data?: Conversation[] }).data ?? [];
    } catch {
      // noop — we'll still get the next event
    }
  }

  function handleNewConversation() {
    goto('/messages/new');
  }

  function selectConversation(id: string) {
    if (selectedId === id) return;
    // Opening the thread triggers a markConversationRead server-side;
    // clear the badge immediately so there's no perceptible lag.
    conversations = conversations.map((c) =>
      c.id === id ? { ...c, unread_count: 0 } : c,
    );
    goto(`/messages/${id}`);
  }
</script>

<div class="messages-layout" class:has-selection={hasSelection}>
  <aside class="conversations-panel" aria-label={$t('dm.conversations')}>
    <div class="panel-header">
      <h1 class="panel-title">{$t('dm.title')}</h1>
      <button
        type="button"
        class="btn btn-primary btn-sm"
        onclick={handleNewConversation}
      >
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z" />
          <line x1="12" y1="8" x2="12" y2="14" />
          <line x1="9" y1="11" x2="15" y2="11" />
        </svg>
        {$t('dm.new')}
      </button>
    </div>

    {#if loading}
      <div class="panel-loading">
        <Spinner />
      </div>
    {:else if conversations.length === 0}
      <div class="panel-empty">
        <p class="empty-text">{$t('dm.no_conversations')}</p>
        <p class="empty-hint">{$t('dm.no_conversations_hint')}</p>
      </div>
    {:else}
      <div class="conversation-list" role="listbox" aria-label={$t('dm.conversations')}>
        {#each conversations as conversation (conversation.id)}
          <ConversationItem
            {conversation}
            active={selectedId === conversation.id}
            currentUserId={userId}
            onclick={() => selectConversation(conversation.id)}
          />
        {/each}
      </div>
    {/if}
  </aside>

  <section class="content-panel">
    {@render children?.()}
  </section>
</div>

<style>
  .messages-layout {
    display: grid;
    grid-template-columns: 340px 1fr;
    /* AppLayout adds padding-top of (header-height + space-8). Match
       the standalone /messages page's math so the input/footer pin
       to the viewport bottom. */
    height: calc(100vh - var(--header-height) - var(--space-8));
    margin: calc(-1 * var(--space-4));
    overflow: hidden;
  }

  .conversations-panel {
    border-inline-end: 1px solid var(--color-border);
    display: flex;
    flex-direction: column;
    overflow: hidden;
    min-width: 0;
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

  .content-panel {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    min-width: 0;
  }

  /* Mobile: show only one panel at a time — list when on index,
     thread when on a detail route. */
  @media (max-width: 768px) {
    .messages-layout {
      /* Drop the desktop two-column grid entirely on mobile.
         A 340px first column on a 360–414px viewport leaves
         the content panel ~50px wide, so the conversation
         detail (and especially MessageInput) collapses into
         an unusable sliver. */
      display: flex;
      flex-direction: column;

      /* The desktop -16px claw-back compensates for AppLayout's
         desktop padding-inline. On mobile AppLayout uses padding
         space-3 which doesn't need clawing back, and the negative
         margin pushes the layout past the viewport's right edge,
         where it gets clipped by `overflow-x: clip` further up. */
      margin: 0;

      /* 100dvh tracks the dynamic viewport on mobile — `100vh`
         on iOS Safari includes the address bar, so the bottom
         row would slide under it. dvh is the modern fix. The
         subtractions match AppLayout's mobile padding: top
         (header + space-4) and bottom (BottomTabs + safe-area
         + space-2). */
      height: calc(
        100dvh - var(--header-height) - var(--space-4) -
          var(--header-height) - var(--space-2) -
          env(safe-area-inset-bottom, 0px)
      );
      max-width: 100%;
      min-width: 0;
    }

    .conversations-panel,
    .content-panel {
      flex: 1;
      min-height: 0;
      min-width: 0;
      border-inline-end: none;
    }

    .messages-layout.has-selection .conversations-panel {
      display: none;
    }

    .messages-layout:not(.has-selection) .content-panel {
      display: none;
    }
  }
</style>

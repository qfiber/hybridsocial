<script lang="ts">
  import type { Message } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import MessageReactionPicker from '$lib/components/dm/MessageReactionPicker.svelte';
  import { loadReactionCatalog, resolveReaction } from '$lib/utils/message-reactions.js';
  import { translateMessage } from '$lib/api/conversations.js';
  import { effectiveTranslationTarget, translationEnabled } from '$lib/stores/translation.js';
  import { t, availableLocales } from '$lib/stores/i18n.js';
  import { addToast } from '$lib/stores/toast.js';
  import { onMount } from 'svelte';
  import { fly, scale } from 'svelte/transition';
  import { cubicOut } from 'svelte/easing';

  let {
    message,
    conversationId,
    isOwn = false,
    showAvatar = true,
    replyTo = null,
    ondelete,
    onreact,
    onedit,
    onreply,
    onreplyclick,
  }: {
    message: Message;
    conversationId: string;
    isOwn?: boolean;
    showAvatar?: boolean;
    // The message this one is replying to, resolved by the parent (which
    // owns the full message list). When null we render a faded
    // "Original message unavailable" stub so a forgotten reply still
    // shows the quote affordance instead of silently looking like a
    // normal message.
    replyTo?: Message | null;
    ondelete?: (messageId: string) => void;
    onreact?: (messageId: string, emoji: string) => void;
    onedit?: (messageId: string, newContent: string) => Promise<void>;
    // Fired when the user taps "Reply" — parent enters reply-compose mode.
    onreply?: (message: Message) => void;
    // Fired when the user taps the quoted preview at the top of a bubble —
    // parent scrolls to the original message in the thread.
    onreplyclick?: (messageId: string) => void;
  } = $props();

  // Server enforces a 5-minute edit window — mirror it client-side
  // so the Edit button only shows while it's actually usable. Tick
  // every 30 seconds so the button auto-disappears at the cutoff
  // without needing a page refresh.
  const EDIT_WINDOW_MS = 5 * 60 * 1000;
  let nowTick = $state(Date.now());
  $effect(() => {
    if (!isOwn || !onedit) return;
    const interval = setInterval(() => {
      nowTick = Date.now();
    }, 30_000);
    return () => clearInterval(interval);
  });
  let canEdit = $derived.by(() => {
    if (!isOwn || !onedit) return false;
    const created = new Date(message.created_at).getTime();
    return nowTick - created < EDIT_WINDOW_MS;
  });

  let formattedTime = $derived(
    new Date(message.created_at).toLocaleTimeString(undefined, {
      hour: 'numeric',
      minute: '2-digit'
    })
  );

  // Read receipts: 3-state if the server told us, fall back to the
  // older 2-state read_at flag for legacy responses that don't include
  // `delivery_status` yet.
  let deliveryStatus = $derived(
    message.delivery_status ?? (message.read_at ? 'read' : 'sent'),
  );
  let isPending = $derived(!!message.pending);

  // Compact one-line preview of the replied-to message — content
  // first, falling back to "Attachment" so a reply to a photo with no
  // caption still gets a recognisable quote chip.
  let replyPreview = $derived.by(() => {
    if (!replyTo) return null;
    const text = (replyTo.content || '').trim();
    if (text) return text;
    if ((replyTo.media_attachments || []).length > 0) return 'Attachment';
    return '';
  });
  let replyAuthor = $derived(
    replyTo?.sender?.display_name || replyTo?.sender?.handle || '',
  );
  let mediaAttachments = $derived(message.media_attachments || []);
  let reactions = $derived(message.reactions || []);
  let sender = $derived(message.sender || {});

  let pickerOpen = $state(false);
  let pickerAbove = $state(false);
  let pickerOpensLeft = $state(false);
  let reactionButtonEl: HTMLButtonElement | undefined = $state();
  let confirmingDelete = $state(false);
  let editing = $state(false);
  let editDraft = $state('');
  let savingEdit = $state(false);

  // Conservative guesses for where the picker needs room. The picker
  // isn't mounted yet at the moment we decide placement, so it can't
  // be measured — these match the 2-row emoji layout plus a small
  // buffer so a loaded premium catalog doesn't overflow unexpectedly.
  const PICKER_ESTIMATED_HEIGHT = 140;
  const PICKER_ESTIMATED_WIDTH = 320;
  const VIEWPORT_SAFETY_PAD = 12;

  $effect(() => {
    if (!pickerOpen || !reactionButtonEl) return;
    const rect = reactionButtonEl.getBoundingClientRect();

    // Vertical: flip above when there isn't room below.
    pickerAbove = window.innerHeight - rect.bottom < PICKER_ESTIMATED_HEIGHT;

    // Horizontal: default is opening rightward from the button's left
    // edge. Flip to leftward only when opening rightward would push
    // the picker past the viewport's right edge.
    pickerOpensLeft =
      rect.left + PICKER_ESTIMATED_WIDTH + VIEWPORT_SAFETY_PAD > window.innerWidth;
  });

  // Debounce timers for the hover-open picker. Open after a short
  // intent delay so a quick scroll-past doesn't pop the picker; close
  // a bit slower so users have time to move into the picker without
  // it dismissing from under them.
  const OPEN_DELAY = 150;
  const CLOSE_DELAY = 250;
  let openTimer: ReturnType<typeof setTimeout> | null = null;
  let closeTimer: ReturnType<typeof setTimeout> | null = null;

  function clearTimers() {
    if (openTimer) {
      clearTimeout(openTimer);
      openTimer = null;
    }
    if (closeTimer) {
      clearTimeout(closeTimer);
      closeTimer = null;
    }
  }

  function schedulePickerOpen() {
    clearTimers();
    openTimer = setTimeout(() => {
      pickerOpen = true;
      openTimer = null;
    }, OPEN_DELAY);
  }

  function schedulePickerClose() {
    clearTimers();
    closeTimer = setTimeout(() => {
      pickerOpen = false;
      closeTimer = null;
    }, CLOSE_DELAY);
  }

  function togglePickerClick(e: MouseEvent) {
    e.stopPropagation();
    clearTimers();
    pickerOpen = !pickerOpen;
  }

  // The reaction catalog is loaded once and cached at module level;
  // we just need a re-render trigger after the fetch resolves so the
  // {#each} below re-runs `resolveReaction` for any premium codes.
  let catalogReady = $state(false);
  onMount(() => {
    loadReactionCatalog()
      .then(() => (catalogReady = true))
      .catch(() => (catalogReady = true));

    return () => clearTimers();
  });

  let resolvedReactions = $derived.by(() => {
    void catalogReady;
    return reactions.map((r) => ({ ...r, display: resolveReaction(r.emoji) }));
  });

  function handleReact(emoji: string) {
    pickerOpen = false;
    onreact?.(message.id, emoji);
  }

  function requestDelete(e: MouseEvent) {
    e.stopPropagation();
    confirmingDelete = true;
  }

  function confirmDelete() {
    confirmingDelete = false;
    ondelete?.(message.id);
  }

  function cancelDelete() {
    confirmingDelete = false;
  }

  function startEdit(e: MouseEvent) {
    e.stopPropagation();
    editDraft = message.content || '';
    editing = true;
  }

  function cancelEdit() {
    editing = false;
    editDraft = '';
  }

  async function saveEdit() {
    if (!onedit || savingEdit) return;
    const trimmed = editDraft.trim();
    if (trimmed === '' || trimmed === message.content) {
      cancelEdit();
      return;
    }
    savingEdit = true;
    try {
      await onedit(message.id, trimmed);
      editing = false;
    } finally {
      savingEdit = false;
    }
  }

  function handleEditKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      cancelEdit();
    } else if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      saveEdit();
    }
  }

  // --- Translation ---
  // Fetched lazily and cached, then the body swaps to it and the toggle
  // relabels to "Show original". Mirrors the post translate affordance, reusing
  // the same instance capability and target-language preference.
  let translatedText = $state<string | null>(null);
  let translating = $state(false);
  let showingTranslation = $state(false);

  let translateTargetName = $derived.by(() => {
    const code = $effectiveTranslationTarget;
    const meta = $availableLocales.find((l) => l.code === code);
    return meta?.nativeName || meta?.name || code.toUpperCase();
  });

  // Offer translation when the instance has a backend and the message carries
  // plaintext (encrypted-only bodies have no `content` to send).
  let canTranslate = $derived($translationEnabled && !!(message.content || '').trim());

  async function handleTranslate(e: MouseEvent) {
    e.stopPropagation();
    if (showingTranslation) {
      showingTranslation = false;
      return;
    }
    if (translatedText !== null) {
      showingTranslation = true;
      return;
    }
    translating = true;
    try {
      const res = await translateMessage(conversationId, message.id, $effectiveTranslationTarget);
      translatedText = res.content;
      showingTranslation = true;
    } catch {
      addToast($t('post.translate_failed'), 'error');
    } finally {
      translating = false;
    }
  }
</script>

<div
  class="message-row"
  class:own={isOwn}
  class:pending={isPending}
  in:fly={{ y: 24, duration: 280, easing: cubicOut }}
>
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

  <div class="bubble-wrapper" class:wrapper-own={isOwn}>
    <div class="bubble" class:bubble-own={isOwn} class:bubble-other={!isOwn}>
      {#if message.reply_to_id}
        <button
          type="button"
          class="reply-quote"
          class:reply-quote-clickable={!!onreplyclick && !!replyTo}
          onclick={() => replyTo && onreplyclick?.(replyTo.id)}
          disabled={!onreplyclick || !replyTo}
        >
          <span class="reply-quote-bar" aria-hidden="true"></span>
          <span class="reply-quote-body">
            <span class="reply-quote-author">
              {replyTo ? replyAuthor || 'Unknown' : 'Original message unavailable'}
            </span>
            {#if replyPreview}
              <span class="reply-quote-text" dir="auto">{replyPreview}</span>
            {/if}
          </span>
        </button>
      {/if}
      {#if editing}
        <div
          class="edit-shell"
          transition:scale={{ start: 0.95, duration: 150, easing: cubicOut }}
        >
          <textarea
            class="edit-textarea"
            bind:value={editDraft}
            onkeydown={handleEditKeydown}
            disabled={savingEdit}
            rows="2"
            aria-label="Edit message"
            autofocus
          ></textarea>
          <div class="edit-actions">
            <button
              type="button"
              class="btn-mini"
              onclick={cancelEdit}
              disabled={savingEdit}
            >
              Cancel
            </button>
            <button
              type="button"
              class="btn-mini btn-mini-primary"
              onclick={saveEdit}
              disabled={savingEdit || editDraft.trim() === ''}
            >
              {savingEdit ? 'Saving…' : 'Save'}
            </button>
          </div>
          <span class="edit-hint">Enter to save, Esc to cancel.</span>
        </div>
      {:else if showingTranslation && translatedText !== null}
        <p class="message-text" dir="auto">{translatedText}</p>
      {:else if message.content_html}
        <div class="message-body" dir="auto">
          {@html message.content_html}
        </div>
      {:else}
        <p class="message-text" dir="auto">{message.content}</p>
      {/if}

      {#if canTranslate && !editing}
        <button
          type="button"
          class="msg-translate-btn"
          onclick={handleTranslate}
          disabled={translating}
        >
          <span class="material-symbols-outlined msg-translate-icon">translate</span>
          {#if translating}
            {$t('post.translating')}
          {:else if showingTranslation}
            {$t('post.show_original')}
          {:else}
            {$t('post.translate_to', { lang: translateTargetName })}
          {/if}
        </button>
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
            {:else if attachment.type === 'gifv'}
              <!-- Looping muted clip, GIF-style. -->
              <video
                src={attachment.url}
                class="media-video"
                autoplay
                loop
                muted
                playsinline
              ></video>
            {:else if attachment.type === 'video'}
              <video src={attachment.url} controls preload="metadata" class="media-video">
                <track kind="captions" />
              </video>
            {:else if attachment.type === 'audio'}
              <audio src={attachment.url} controls preload="metadata" class="media-audio"></audio>
            {:else}
              <!-- Any other attachment (generic file) — a download chip so
                   it never renders as an empty bubble. -->
              <a
                class="media-file"
                href={attachment.url}
                target="_blank"
                rel="noopener noreferrer"
              >
                <span class="material-symbols-outlined media-file-icon" aria-hidden="true">description</span>
                <span class="media-file-name">{attachment.description || 'Attachment'}</span>
                <span class="material-symbols-outlined media-file-dl" aria-hidden="true">download</span>
              </a>
            {/if}
          {/each}
        </div>
      {/if}

      <div class="message-meta">
        <time class="message-time" datetime={message.created_at}>{formattedTime}</time>
        {#if message.edited_at}
          <span class="message-edited">edited</span>
        {/if}
        {#if isPending}
          <span class="message-pending">sending...</span>
        {:else if isOwn}
          <span
            class="read-receipt"
            class:tick-delivered={deliveryStatus === 'delivered'}
            class:tick-read={deliveryStatus === 'read'}
            aria-label={
              deliveryStatus === 'read'
                ? 'Read'
                : deliveryStatus === 'delivered'
                  ? 'Delivered'
                  : 'Sent'
            }
            title={
              deliveryStatus === 'read'
                ? 'Read'
                : deliveryStatus === 'delivered'
                  ? 'Delivered'
                  : 'Sent'
            }
          >
            <svg
              width="14"
              height="14"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              {#if deliveryStatus === 'sent'}
                <!-- single tick -->
                <polyline points="4 12 8 16 16 8" />
              {:else}
                <!-- double tick — colored via .tick-read when seen -->
                <polyline points="1 12 5 16 12 9" />
                <polyline points="7 12 11 16 18 9" />
              {/if}
            </svg>
          </span>
        {/if}
      </div>

      {#if resolvedReactions.length > 0}
        <div class="reactions-overlay" class:overlay-own={isOwn}>
          {#each resolvedReactions as r (r.emoji)}
            <span
              class="msg-reaction"
              title="{r.count} × :{r.emoji}:"
              transition:scale={{ start: 0.6, duration: 200, easing: cubicOut }}
            >
              {#if r.display.kind === 'image'}
                <img class="msg-reaction-img" src={r.display.src} alt="" />
              {:else if r.display.kind === 'char'}
                <span class="msg-reaction-char">{r.display.value}</span>
              {:else}
                <span class="msg-reaction-fallback">:{r.display.value}:</span>
              {/if}
              {#if r.count > 1}<span class="msg-reaction-count">{r.count}</span>{/if}
            </span>
          {/each}
        </div>
      {/if}
    </div>

    {#if !isPending && !editing}
      <div class="bubble-actions">
        <!-- Hover-zone wraps the smiley button + the picker so moving
             between them doesn't trigger a close. -->
        <div
          class="reaction-hover-zone"
          onmouseenter={schedulePickerOpen}
          onmouseleave={schedulePickerClose}
          role="presentation"
        >
          <button
            type="button"
            class="bubble-action-btn"
            title="Add reaction"
            aria-label="Add reaction"
            aria-expanded={pickerOpen}
            bind:this={reactionButtonEl}
            onclick={togglePickerClick}
          >
            <span class="material-symbols-outlined">add_reaction</span>
          </button>

          {#if pickerOpen}
            <div
              class="picker-anchor"
              class:picker-anchor-left={pickerOpensLeft}
              class:picker-anchor-right={!pickerOpensLeft}
              class:picker-anchor-above={pickerAbove}
              transition:fly={{ y: pickerAbove ? 6 : -6, duration: 180, easing: cubicOut }}
            >
              <MessageReactionPicker
                onpick={handleReact}
                onclose={() => (pickerOpen = false)}
              />
            </div>
          {/if}
        </div>

        {#if onreply}
          <button
            type="button"
            class="bubble-action-btn"
            title="Reply"
            aria-label="Reply to message"
            onclick={() => onreply?.(message)}
          >
            <span class="material-symbols-outlined">reply</span>
          </button>
        {/if}

        {#if canEdit}
          <button
            type="button"
            class="bubble-action-btn"
            title="Edit message (5 min window)"
            aria-label="Edit message"
            onclick={startEdit}
          >
            <span class="material-symbols-outlined">edit</span>
          </button>
        {/if}

        {#if isOwn && ondelete}
          <button
            type="button"
            class="bubble-action-btn bubble-action-danger"
            title="Delete message"
            aria-label="Delete message"
            onclick={requestDelete}
          >
            <span class="material-symbols-outlined">delete</span>
          </button>
        {/if}
      </div>

      {#if confirmingDelete}
        <div
          class="delete-confirm"
          role="alertdialog"
          aria-live="polite"
          transition:fly={{ y: -6, duration: 180, easing: cubicOut }}
        >
          <span class="delete-confirm-text">Delete this message?</span>
          <div class="delete-confirm-actions">
            <button type="button" class="btn-mini" onclick={cancelDelete}>Cancel</button>
            <button type="button" class="btn-mini btn-mini-danger" onclick={confirmDelete}>
              Delete
            </button>
          </div>
        </div>
      {/if}
    {/if}
  </div>
</div>

<style>
  .message-row {
    display: flex;
    align-items: flex-end;
    gap: var(--space-2);
    /* Extra block-end so the half-outside reaction chips don't visually
       collide with the next bubble underneath. */
    margin-block-end: 14px;
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

  .bubble-wrapper {
    position: relative;
    display: flex;
    align-items: flex-end;
    gap: 4px;
    max-width: 75%;
  }

  .wrapper-own {
    margin-inline-start: auto;
    flex-direction: row-reverse;
  }

  .bubble {
    position: relative;
    padding: var(--space-2) var(--space-3);
    word-break: break-word;
  }

  /* Own messages: a solid accent bubble with on-primary text — a clear,
     iMessage-style distinction from received messages (the previous
     faint tint read almost identically to received). */
  .bubble-own {
    background: var(--gradient-primary);
    color: var(--color-text-on-primary);
    border-radius: var(--radius-xl) var(--radius-xl) var(--radius-xs) var(--radius-xl);
  }

  .bubble-other {
    background: var(--color-surface-container-low);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl) var(--radius-xl) var(--radius-xl) var(--radius-xs);
  }

  /* Flip all inner content to the on-primary palette on the accent
     bubble so text, links, meta and ticks stay legible. */
  .bubble-own .message-text,
  .bubble-own .message-body,
  .bubble-own .message-body :global(*) {
    color: var(--color-text-on-primary);
  }

  .bubble-own .message-body :global(a) {
    text-decoration: underline;
  }

  .bubble-own .message-time,
  .bubble-own .message-edited,
  .bubble-own .message-pending,
  .bubble-own .read-receipt,
  .bubble-own .read-receipt.tick-delivered {
    color: rgba(255, 255, 255, 0.75);
  }

  .bubble-own .read-receipt.tick-read {
    color: #ffffff;
  }

  /* Quoted-reply preview at the top of a bubble. The left bar uses
     the bubble's own background, so it sits more like an indentation
     than a separate chip — matches Telegram / Signal / WhatsApp. */
  .reply-quote {
    display: flex;
    gap: var(--space-2);
    align-items: stretch;
    width: 100%;
    margin-block-end: var(--space-1);
    padding: 4px 8px;
    border: none;
    background: var(--color-bg);
    border-radius: var(--radius-sm);
    color: var(--color-text-secondary);
    text-align: start;
    overflow: hidden;
    /* Click target is a button so screen-reader semantics are right.
       Reset the default user-agent styles so it visually feels like
       part of the bubble, not a control. */
    font: inherit;
  }

  .reply-quote-clickable {
    cursor: pointer;
  }

  .reply-quote-clickable:hover {
    background: var(--color-surface);
  }

  .reply-quote:disabled {
    cursor: default;
    opacity: 0.7;
  }

  .reply-quote-bar {
    flex-shrink: 0;
    width: 3px;
    border-radius: 999px;
    background: var(--color-primary);
  }

  .reply-quote-body {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    flex: 1;
  }

  .reply-quote-author {
    font-size: 12px;
    font-weight: 600;
    color: var(--color-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .reply-quote-text {
    font-size: 12px;
    color: var(--color-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .bubble-actions {
    display: flex;
    align-items: center;
    gap: 2px;
    opacity: 0;
    /* Slide in slightly from the bubble side as we fade — feels
       intentional rather than just appearing. Direction is set per
       wrapper below so the slide always comes FROM the bubble. */
    transform: translateX(-4px);
    transition:
      opacity var(--transition-fast),
      transform var(--transition-fast);
    flex-shrink: 0;
  }

  .wrapper-own .bubble-actions {
    transform: translateX(4px);
  }

  .bubble-wrapper:hover .bubble-actions,
  .bubble-wrapper:focus-within .bubble-actions {
    opacity: 1;
    transform: translateX(0);
  }

  .bubble-action-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    padding: 0;
    background: var(--color-surface-raised, var(--color-surface));
    border: 1px solid var(--color-border);
    border-radius: 50%;
    cursor: pointer;
    color: var(--color-text-secondary);
    transition:
      background-color var(--transition-fast),
      color var(--transition-fast),
      border-color var(--transition-fast),
      transform var(--transition-fast);
  }

  .bubble-action-btn:hover {
    background: var(--color-surface);
    color: var(--color-text);
    border-color: var(--color-text-tertiary);
    transform: scale(1.08);
  }

  .bubble-action-btn .material-symbols-outlined {
    font-size: 16px !important;
  }

  .bubble-action-danger:hover {
    color: var(--color-danger, #b00);
    border-color: var(--color-danger, #b00);
  }

  /* Touch devices have no hover — show actions inline so users can tap them. */
  @media (hover: none) {
    .bubble-actions {
      opacity: 1;
    }
  }

  .reaction-hover-zone {
    position: relative;
    display: inline-flex;
  }

  /* Each .message-row creates its own stacking context via the ripple
     animation's will-change (and later rows paint on top in DOM order),
     so a local z-index on .picker-anchor can't escape upward — later
     bubbles would cover the picker. Promote the host row while the
     picker is open so it paints above its siblings. */
  :global(.message-row:has(.picker-anchor)) {
    position: relative;
    z-index: 50;
  }

  .picker-anchor {
    position: absolute;
    top: 100%;
    z-index: var(--z-dropdown, 100);
    margin-top: 4px;
  }

  /* Opening leftward (picker's right edge at the button's right edge).
     Default when there's room — keeps the picker close to the bubble
     for other-person messages (button on the bubble's right side). */
  .picker-anchor-left {
    right: 0;
    left: auto;
  }

  /* Opening rightward (picker's left edge at the button's left edge).
     Used when the button is too close to the viewport's left edge —
     prevents the picker from clipping into the sidebar. Typically
     fires for own-message reaction buttons in LTR mode. */
  .picker-anchor-right {
    left: 0;
    right: auto;
  }

  /* Not enough room below (message near the composer at the bottom
     of the chat). Flip the picker above the button. */
  .picker-anchor-above {
    top: auto;
    bottom: 100%;
    margin-top: 0;
    margin-bottom: 4px;
  }

  .delete-confirm {
    position: absolute;
    inset-block-start: 100%;
    inset-inline-end: 0;
    z-index: var(--z-dropdown, 100);
    margin-block-start: 4px;
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface-raised, var(--color-surface));
    border: 1px solid var(--color-danger, #b00);
    border-radius: var(--radius-md, 8px);
    box-shadow: var(--shadow-md);
    white-space: nowrap;
  }

  .delete-confirm-text {
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  .delete-confirm-actions {
    display: flex;
    gap: 4px;
  }

  .btn-mini {
    padding: 4px 10px;
    border: none;
    background: transparent;
    border-radius: 6px;
    font-size: var(--text-xs);
    font-weight: 600;
    cursor: pointer;
    color: var(--color-text-secondary);
  }

  .btn-mini:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .btn-mini-danger {
    background: var(--color-danger, #b00);
    color: white;
  }

  .btn-mini-danger:hover {
    background: var(--color-danger, #900);
    color: white;
  }

  .btn-mini-primary {
    background: var(--color-primary, #3b82f6);
    color: white;
  }

  .btn-mini-primary:hover {
    background: var(--color-primary-hover, #2563eb);
    color: white;
  }

  /* Inline edit shell */
  .edit-shell {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 180px;
  }

  .edit-textarea {
    width: 100%;
    padding: 6px 8px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm, 4px);
    background: var(--color-surface, white);
    color: var(--color-text);
    font: inherit;
    font-size: var(--text-sm);
    resize: vertical;
    min-height: 56px;
  }

  .edit-actions {
    display: flex;
    justify-content: flex-end;
    gap: 4px;
  }

  .edit-hint {
    font-size: 10px;
    color: var(--color-text-tertiary);
    text-align: end;
  }

  .message-text {
    font-size: var(--text-sm);
    line-height: 1.5;
    color: var(--color-text);
    unicode-bidi: plaintext;
  }

  .message-body {
    font-size: var(--text-sm);
    line-height: 1.5;
    color: var(--color-text);
  }

  /* Quiet translate toggle under the message text. */
  .msg-translate-btn {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    margin-block-start: 3px;
    padding: 0;
    background: none;
    border: none;
    cursor: pointer;
    color: var(--color-primary);
    font: inherit;
    font-size: 0.6875rem;
    font-weight: 600;
    opacity: 0.9;
  }

  .msg-translate-btn:hover:not(:disabled) {
    text-decoration: underline;
  }

  .msg-translate-btn:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .msg-translate-icon {
    font-size: 14px !important;
  }

  /* On the accent (own) bubble, tint the toggle to the on-primary palette so
     it stays legible against the gradient. */
  .bubble-own .msg-translate-btn {
    color: rgba(255, 255, 255, 0.9);
  }

  /* Per-paragraph direction inside message bodies — pairs with
     `dir="auto"` on the wrapper so Arabic/English/Hebrew mixed in
     one message each flip correctly. */
  .message-body :global(p),
  .message-body :global(li),
  .message-body :global(blockquote) {
    unicode-bidi: plaintext;
  }

  .message-media {
    margin-block-start: var(--space-2);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .media-image {
    border-radius: var(--radius-lg);
    max-width: 100%;
    max-height: 320px;
    object-fit: cover;
  }

  .media-video {
    border-radius: var(--radius-lg);
    max-width: 100%;
    max-height: 320px;
  }

  .media-audio {
    width: 260px;
    max-width: 100%;
    height: 40px;
  }

  /* Generic file / unknown attachment → a tappable download chip.
     `color: inherit` so it reads on-primary inside own (accent) bubbles. */
  .media-file {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-lg);
    background: rgba(127, 127, 127, 0.12);
    color: inherit;
    text-decoration: none;
    max-width: 260px;
  }

  .media-file-name {
    flex: 1;
    min-width: 0;
    font-size: var(--text-sm);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .media-file-icon,
  .media-file-dl {
    font-size: 20px;
    flex-shrink: 0;
    opacity: 0.85;
  }

  .message-meta {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    margin-block-start: var(--space-1);
    /* Received bubbles read left-to-right, so their meta hugs the start;
       own (right-aligned) bubbles hug the end. */
    justify-content: flex-start;
  }

  .bubble-own .message-meta {
    justify-content: flex-end;
  }

  .message-time {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .message-edited {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    font-style: italic;
  }

  .read-receipt {
    color: var(--color-text-tertiary);
    display: flex;
    align-items: center;
  }

  /* Delivered = 2 ticks, still grey. Read = 2 ticks coloured in the
     accent — same convention WhatsApp / Telegram use. */
  .read-receipt.tick-delivered {
    color: var(--color-text-secondary);
  }

  .read-receipt.tick-read {
    color: var(--color-primary);
  }

  .pending {
    opacity: 0.6;
  }

  .message-pending {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    font-style: italic;
  }

  /* Reactions sit half-outside the bubble's bottom edge — anchor
     to the inside-corner so the chip overlaps the rounded edge.
     Physical left/right (not logical inset-inline-*) so an RTL
     `dir="auto"` on the message text inside the bubble can't flip
     the overlay's own axis. */
  .reactions-overlay {
    position: absolute;
    bottom: -12px;
    left: 12px;
    right: auto;
    display: flex;
    flex-direction: row;
    gap: 3px;
    z-index: 1;
    pointer-events: none;
  }

  .reactions-overlay :global(.msg-reaction) {
    pointer-events: auto;
  }

  /* Own bubble (right side) — bleed out the bottom-RIGHT instead. */
  .overlay-own {
    left: auto;
    right: 12px;
  }

  .msg-reaction {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    padding: 2px 6px;
    border-radius: 9999px;
    background: var(--color-surface-raised, var(--color-surface));
    border: 1px solid var(--color-border);
    box-shadow: var(--shadow-sm);
    font-size: 0.875rem;
    line-height: 1;
    cursor: default;
  }

  .msg-reaction-char {
    font-size: 14px;
    line-height: 1;
  }

  .msg-reaction-img {
    width: 16px;
    height: 16px;
    object-fit: contain;
    display: block;
  }

  .msg-reaction-fallback {
    font-family: var(--font-mono, ui-monospace, monospace);
    font-size: 0.6875rem;
    color: var(--color-text-tertiary);
  }

  .msg-reaction-count {
    font-size: 0.6875rem;
    font-weight: 700;
    color: var(--color-text-secondary);
    margin-inline-start: 2px;
  }
</style>

<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { goto } from '$app/navigation';
  import { lockScroll } from '$lib/utils/scroll-lock.js';
  import ReactionPicker from '$lib/components/post/ReactionPicker.svelte';
  import { premiumCatalog, ensurePremiumCatalog } from '$lib/stores/reaction-catalog.js';
  import { getPostContext } from '$lib/api/statuses.js';
  import type { Post } from '$lib/api/types.js';
  import { relativeTime } from '$lib/utils/time.js';
  import { api, ApiError } from '$lib/api/client.js';
  import { currentUser } from '$lib/stores/auth.js';
  import { t } from '$lib/stores/i18n.js';
  import { tError } from '$lib/utils/i18n.js';

  interface Slide {
    url: string;
    alt?: string | null;
    /** Media attachment id — required for the per-image reply button. */
    id?: string;
    /** Server-reported reaction count for this image (Instagram-style). */
    reactionCount?: number;
    /**
     * The viewer's current reaction shortcode (e.g. "like", "fire") or
     * null if they haven't reacted. Drives the heart fill / glyph and
     * lets the picker mark the active choice.
     */
    currentReaction?: string | null;
  }

  let {
    images,
    index = $bindable(0),
    postId,
    onclose,
    onreply,
    onreact,
    postVisibility,
  }: {
    images: Slide[];
    index?: number;
    /**
     * Parent post id. When supplied alongside a slide that has an `id`,
     * the lightbox fetches replies pinned to the current image and
     * shows them in a side panel (auto-hidden when none exist).
     */
    postId?: string;
    onclose: () => void;
    /**
     * If supplied, the lightbox surfaces a "Reply to this image"
     * button. Receives the targeted media's id and its 1-based index
     * within the parent post's gallery so the composer can show a
     * thumbnail + label and submit `target_media_id`.
     */
    onreply?: (mediaId: string, mediaIndex: number) => void;
    /**
     * Per-image reaction. `next` is the chosen reaction shortcode
     * (e.g. "like", "love", "fire") or `null` to remove the current
     * reaction. Caller is expected to POST/DELETE
     * /api/v1/statuses/:id/react with `target_media_id` and update
     * the slide's `currentReaction` / `reactionCount`.
     */
    onreact?: (mediaId: string, next: string | null) => void;
    /**
     * The parent post's visibility. A comment written in the panel keeps it
     * (a public reply to a followers-only post would leak the thread).
     */
    postVisibility?: string;
  } = $props();

  // Pull the premium catalog so we can render the user's currently
  // selected emoji on the heart button and on the burst animation
  // even when it's a premium glyph like 🔥.
  ensurePremiumCatalog();

  const DEFAULT_REACTION_EMOJI: Record<string, string> = {
    like: '\u{1F44D}',
    love: '\u{2764}\u{FE0F}',
    wow: '\u{1F92F}',
    care: '\u{1F970}',
    angry: '\u{1F621}',
    sad: '\u{1F622}',
    lol: '\u{1F602}',
  };

  let pickerOpen = $state(false);
  let pickerHoverTimer: ReturnType<typeof setTimeout> | null = null;

  let zoomed = $state(false);
  // Instagram-style double-tap-to-like: when the user taps the image
  // twice in quick succession AND the host wired up onreact, fire the
  // reaction and play a heart-burst animation tied to the image.
  let lastTapAt = $state(0);
  let burstAt = $state(0);

  let current = $derived(images[index] ?? images[0]);
  let hasPrev = $derived(index > 0);
  let hasNext = $derived(index < images.length - 1);

  // Per-image replies sidebar. Cached by media id so flipping back
  // to a slide we've already loaded doesn't refetch. Only populated
  // when both `postId` and `current.id` are present — drives the
  // panel's visibility (hidden when the array is empty for the
  // current slide).
  let repliesByMedia = $state<Record<string, Post[]>>({});
  let repliesLoading = $state(false);
  let currentReplies = $derived(
    current?.id ? (repliesByMedia[current.id] ?? []) : [],
  );
  // The panel also opens on demand (the comment button) so the first comment
  // on an image can be written here too, not only further ones.
  let panelOpen = $state(false);
  let canComment = $derived(!!postId && !!current?.id && !!$currentUser);
  let showSidebar = $derived(
    !!postId && !!current?.id && (currentReplies.length > 0 || panelOpen),
  );

  // --- Writing a comment on this image ---------------------------------------
  let draft = $state('');
  let sending = $state(false);
  let sendError = $state('');
  let inputEl: HTMLTextAreaElement | undefined = $state();

  function openPanel() {
    panelOpen = true;
    // Wait for the panel to mount, then focus its field.
    setTimeout(() => inputEl?.focus(), 0);
  }

  function handleCommentButton() {
    if (canComment) openPanel();
    else if (onreply && current?.id) onreply(current.id, index + 1);
  }

  function autosize() {
    if (!inputEl) return;
    inputEl.style.height = 'auto';
    inputEl.style.height = `${Math.min(inputEl.scrollHeight, 120)}px`;
  }

  function onInputKey(e: KeyboardEvent) {
    // Keep the viewer's own shortcuts (Esc closes, arrows flip, Space/Z zoom)
    // from firing while typing.
    e.stopPropagation();
    const touch = window.matchMedia('(pointer: coarse)').matches;
    if (e.key === 'Enter' && !e.shiftKey && !touch) {
      e.preventDefault();
      sendComment();
    } else if (e.key === 'Escape') {
      e.preventDefault();
      inputEl?.blur();
    }
  }

  async function sendComment() {
    const text = draft.trim();
    const mediaId = current?.id;
    if (!text || !postId || !mediaId || sending) return;
    sending = true;
    sendError = '';
    const visibility =
      postVisibility === 'followers' || postVisibility === 'direct' ? postVisibility : 'public';
    try {
      const reply = await api.post<Post>('/api/v1/statuses', {
        content: text,
        visibility,
        parent_id: postId,
        target_media_id: mediaId,
      });
      draft = '';
      setTimeout(autosize, 0);
      const existing = repliesByMedia[mediaId] ?? [];
      if (!existing.some((r) => r.id === reply.id)) {
        repliesByMedia = { ...repliesByMedia, [mediaId]: [...existing, reply] };
      }
      // Let the feed's thread and counters know, like the composer does.
      window.dispatchEvent(new CustomEvent('new-post', { detail: reply }));
      window.dispatchEvent(
        new CustomEvent('reply-count-update', { detail: { postId, delta: 1 } }),
      );
    } catch (err) {
      const code = err instanceof ApiError ? (err.body as { error?: string } | null)?.error : undefined;
      sendError = code?.startsWith('trust.') ? tError(code) : $t('composer.publish_failed');
    } finally {
      sending = false;
    }
  }

  // The full composer (media, formatting) for this image.
  function openFullComposer() {
    if (onreply && current?.id) onreply(current.id, index + 1);
  }

  $effect(() => {
    const mediaId = current?.id;
    if (!postId || !mediaId) return;
    // Avoid re-fetching when we already have a result for this slide.
    if (untrack(() => repliesByMedia[mediaId] !== undefined)) return;
    let cancelled = false;
    repliesLoading = true;
    getPostContext(postId, { mediaId })
      .then((ctx) => {
        if (cancelled) return;
        // Backend returns the full subtree for the targeted image.
        // Show only direct replies in the panel — nested threads stay
        // accessible via clicking through to the post detail.
        const direct = (ctx.descendants || []).filter(
          (d) => d.parent_id === postId && !d.tombstone,
        );
        repliesByMedia = { ...repliesByMedia, [mediaId]: direct };
      })
      .catch(() => {
        if (cancelled) return;
        repliesByMedia = { ...repliesByMedia, [mediaId]: [] };
      })
      .finally(() => {
        if (!cancelled) repliesLoading = false;
      });
    return () => {
      cancelled = true;
    };
  });

  function handleNewReply(e: Event) {
    const reply = (e as CustomEvent<Post>).detail;
    if (!reply || !postId) return;
    if (reply.parent_id !== postId) return;
    const mediaId = reply.target_media_id;
    if (!mediaId) return;
    const existing = repliesByMedia[mediaId] ?? [];
    if (existing.some((r) => r.id === reply.id)) return;
    repliesByMedia = { ...repliesByMedia, [mediaId]: [...existing, reply] };
  }

  function openReplyDetail(replyId: string) {
    onclose();
    goto(`/post/${replyId}`);
  }

  function close() {
    onclose();
  }

  function prev() {
    if (hasPrev) {
      index = index - 1;
      zoomed = false;
    }
  }

  function next() {
    if (hasNext) {
      index = index + 1;
      zoomed = false;
    }
  }

  function toggleZoom() {
    zoomed = !zoomed;
  }

  function handleImageTap() {
    const now = performance.now();
    // 320ms is the standard double-tap window; longer than that and we
    // treat it as two separate single taps (which fall through to the
    // default zoom-toggle behaviour below).
    const isDoubleTap = now - lastTapAt < 320;
    lastTapAt = now;

    if (isDoubleTap && onreact && current?.id && !current.currentReaction) {
      onreact(current.id, 'like');
      burstAt = now;
      return;
    }

    if (!isDoubleTap) {
      toggleZoom();
    }
  }

  // Heart button: a single click toggles the default thumbs-up,
  // hover/long-press opens the full reaction picker (7 default + 7
  // premium for premium tiers).
  function handleHeartClick() {
    if (!onreact || !current?.id) return;
    if (current.currentReaction) {
      // Already reacted — toggle off.
      onreact(current.id, null);
    } else {
      onreact(current.id, 'like');
      burstAt = performance.now();
    }
  }

  function handleHeartEnter() {
    if (pickerHoverTimer) clearTimeout(pickerHoverTimer);
    pickerHoverTimer = setTimeout(() => {
      pickerOpen = true;
    }, 220);
  }

  function handleHeartLeave() {
    if (pickerHoverTimer) clearTimeout(pickerHoverTimer);
    pickerHoverTimer = setTimeout(() => {
      pickerOpen = false;
    }, 180);
  }

  function handlePickerKeep() {
    if (pickerHoverTimer) clearTimeout(pickerHoverTimer);
  }

  function handlePickerSelect(type: string) {
    if (!onreact || !current?.id) return;
    pickerOpen = false;
    if (current.currentReaction === type) {
      onreact(current.id, null);
    } else {
      onreact(current.id, type);
      burstAt = performance.now();
    }
  }

  // Resolve a reaction shortcode to an emoji char or image url so the
  // heart button can show what the user picked, and the burst animation
  // can flash the right glyph.
  function reactionGlyph(type: string | null | undefined):
    | { kind: 'char'; value: string }
    | { kind: 'image'; src: string }
    | null {
    if (!type) return null;
    const def = DEFAULT_REACTION_EMOJI[type];
    if (def) return { kind: 'char', value: def };
    const premium = $premiumCatalog.get(type);
    if (premium?.image_url) return { kind: 'image', src: premium.image_url };
    if (premium?.character) return { kind: 'char', value: premium.character };
    return null;
  }

  async function download() {
    // Same-origin images can be triggered via <a download>. Remote
    // images might be blocked by CORS or content-disposition; fall
    // back to opening in a new tab so the user can save manually.
    try {
      const res = await fetch(current.url, { mode: 'cors' });
      const blob = await res.blob();
      const objUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = objUrl;
      a.download = current.url.split('/').pop()?.split('?')[0] || 'image';
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(objUrl), 1000);
    } catch {
      window.open(current.url, '_blank', 'noopener,noreferrer');
    }
  }

  function handleKey(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      if (panelOpen && currentReplies.length === 0) panelOpen = false;
      else close();
    }
    // The prev/next buttons sit on the start/end edges, so in an RTL locale
    // "previous" is on the right — map the arrow keys to match what's seen.
    else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
      const rtl = document.documentElement.dir === 'rtl';
      if ((e.key === 'ArrowLeft') !== rtl) prev();
      else next();
    }
    else if (e.key === ' ' || e.key.toLowerCase() === 'z') {
      e.preventDefault();
      toggleZoom();
    }
  }

  onMount(() => {
    // On <html>, not <body> — a body lock doesn't reach the viewport here
    // (see utils/scroll-lock.ts).
    const unlockScroll = lockScroll();
    window.addEventListener('keydown', handleKey);
    window.addEventListener('new-post', handleNewReply);
    return () => {
      unlockScroll();
      window.removeEventListener('keydown', handleKey);
      window.removeEventListener('new-post', handleNewReply);
    };
  });

  function handleBackdropClick(e: MouseEvent) {
    // Only close if the click was on the backdrop itself, not on a
    // descendant control (zoom/download buttons) or the image.
    if (e.target === e.currentTarget) close();
  }
</script>

<div
  class="lightbox"
  role="dialog"
  aria-modal="true"
  aria-label="Image viewer"
  onclick={handleBackdropClick}
>
  <div class="lightbox-tools-left">
    <button
      type="button"
      class="lightbox-btn"
      onclick={toggleZoom}
      aria-label={zoomed ? 'Fit to screen' : 'Zoom to full size'}
    >
      <span class="material-symbols-outlined">
        {zoomed ? 'zoom_out_map' : 'zoom_in'}
      </span>
    </button>
    <button
      type="button"
      class="lightbox-btn"
      onclick={download}
      aria-label="Download image"
    >
      <span class="material-symbols-outlined">download</span>
    </button>
    {#if onreact && current?.id}
      {@const glyph = reactionGlyph(current.currentReaction)}
      <div
        class="lightbox-react-wrap"
        onmouseenter={handleHeartEnter}
        onmouseleave={handleHeartLeave}
        role="presentation"
      >
        <button
          type="button"
          class="lightbox-btn lightbox-btn-react"
          class:lightbox-btn-reacted={!!current.currentReaction}
          onclick={handleHeartClick}
          aria-label={current.currentReaction ? 'Remove reaction' : 'React to this image'}
          aria-haspopup="dialog"
          aria-expanded={pickerOpen}
          title={current.currentReaction ? 'Click to remove · hover for picker' : 'React to this image'}
        >
          {#if glyph?.kind === 'image'}
            <img class="lightbox-react-img" src={glyph.src} alt="" />
          {:else if glyph?.kind === 'char'}
            <span class="lightbox-react-emoji">{glyph.value}</span>
          {:else}
            <span class="material-symbols-outlined">favorite</span>
          {/if}
          {#if current.reactionCount && current.reactionCount > 0}
            <span class="lightbox-react-count">{current.reactionCount}</span>
          {/if}
        </button>
        {#if pickerOpen}
          <div
            class="lightbox-picker-anchor"
            onmouseenter={handlePickerKeep}
            onmouseleave={handleHeartLeave}
            role="presentation"
          >
            <ReactionPicker
              selected={current.currentReaction ?? null}
              onselect={handlePickerSelect}
            />
          </div>
        {/if}
      </div>
    {/if}
    {#if (onreply || canComment) && current?.id}
      <button
        type="button"
        class="lightbox-btn"
        onclick={handleCommentButton}
        aria-label={$t('lightbox.comment_on_image')}
        title={$t('lightbox.comment_on_image')}
      >
        <span class="material-symbols-outlined">comment</span>
      </button>
    {/if}
  </div>

  <button
    type="button"
    class="lightbox-btn lightbox-close"
    onclick={close}
    aria-label="Close"
  >
    <span class="material-symbols-outlined">close</span>
  </button>

  {#if hasPrev}
    <button type="button" class="lightbox-nav lightbox-nav-prev" onclick={prev} aria-label="Previous image">
      <span class="material-symbols-outlined rtl-mirror">chevron_left</span>
    </button>
  {/if}
  {#if hasNext}
    <button type="button" class="lightbox-nav lightbox-nav-next" onclick={next} aria-label="Next image">
      <span class="material-symbols-outlined rtl-mirror">chevron_right</span>
    </button>
  {/if}

  <div
    class="lightbox-stage"
    class:lightbox-stage-zoomed={zoomed}
    role="presentation"
    onclick={handleBackdropClick}
  >
    <img
      src={current.url}
      alt={current.alt || ''}
      class="lightbox-img"
      class:lightbox-img-zoomed={zoomed}
      draggable="false"
      onclick={(e) => { e.stopPropagation(); handleImageTap(); }}
    />
    {#if burstAt > 0}
      {@const burstGlyph = reactionGlyph(current.currentReaction ?? 'like')}
      {#key burstAt}
        <span class="lightbox-burst" aria-hidden="true">
          {#if burstGlyph?.kind === 'image'}
            <img class="lightbox-burst-img" src={burstGlyph.src} alt="" />
          {:else if burstGlyph?.kind === 'char'}
            <span class="lightbox-burst-emoji">{burstGlyph.value}</span>
          {:else}
            <span class="material-symbols-outlined material-symbols-filled">favorite</span>
          {/if}
        </span>
      {/key}
    {/if}
  </div>

  {#if images.length > 1}
    <div class="lightbox-counter" aria-live="polite">
      {index + 1} / {images.length}
    </div>
  {/if}

  {#if showSidebar}
    <aside class="lightbox-sidebar" aria-label="Replies on this image">
      <header class="lightbox-sidebar-header">
        <svg
          class="sidebar-header-icon"
          viewBox="0 0 24 24"
          width="1em"
          height="1em"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M8 10.5H16M8 14.5H11M21.0039 12C21.0039 16.9706 16.9745 21 12.0039 21C9.9675 21 3.00463 21 3.00463 21C3.00463 21 4.56382 17.2561 3.93982 16.0008C3.34076 14.7956 3.00391 13.4372 3.00391 12C3.00391 7.02944 7.03334 3 12.0039 3C16.9745 3 21.0039 7.02944 21.0039 12Z" />
        </svg>
        <span class="lightbox-sidebar-title">
          {currentReplies.length > 0
            ? $t('lightbox.image_comments', { count: currentReplies.length })
            : $t('lightbox.no_image_comments')}
        </span>
        <button
          type="button"
          class="lightbox-sidebar-close"
          onclick={() => (panelOpen = false)}
          aria-label={$t('lightbox.hide_comments')}
          hidden={currentReplies.length > 0}
        >
          <span class="material-symbols-outlined" aria-hidden="true">close</span>
        </button>
      </header>
      <ul class="lightbox-reply-list">
        {#each currentReplies as reply (reply.id)}
          <li>
            <button
              type="button"
              class="lightbox-reply"
              onclick={() => openReplyDetail(reply.id)}
              aria-label={`Open reply by ${reply.account.display_name || reply.account.handle}`}
            >
              <img
                class="lightbox-reply-avatar"
                src={reply.account.avatar_url || '/images/default-avatar.svg'}
                alt=""
                loading="lazy"
              />
              <div class="lightbox-reply-body">
                <div class="lightbox-reply-meta">
                  <span class="lightbox-reply-name">{reply.account.display_name || reply.account.handle}</span>
                  <span class="lightbox-reply-time">{relativeTime(reply.created_at)}</span>
                </div>
                {#if reply.content_html}
                  <div class="lightbox-reply-text" dir="auto">{@html reply.content_html}</div>
                {:else if reply.content}
                  <p class="lightbox-reply-text" dir="auto">{reply.content}</p>
                {/if}
              </div>
            </button>
          </li>
        {/each}
      </ul>
      {#if canComment}
        <div class="lightbox-comment">
          {#if sendError}
            <p class="lightbox-comment-error" role="alert">{sendError}</p>
          {/if}
          <div class="lightbox-comment-row">
            <textarea
              bind:this={inputEl}
              bind:value={draft}
              class="lightbox-comment-input"
              rows="1"
              dir="auto"
              placeholder={$t('lightbox.comment_placeholder')}
              aria-label={$t('lightbox.comment_placeholder')}
              oninput={autosize}
              onkeydown={onInputKey}
            ></textarea>
            {#if onreply}
              <button
                type="button"
                class="lightbox-comment-btn"
                onclick={openFullComposer}
                aria-label={$t('lightbox.full_composer')}
                title={$t('lightbox.full_composer')}
              >
                <span class="material-symbols-outlined" aria-hidden="true">open_in_full</span>
              </button>
            {/if}
            <button
              type="button"
              class="lightbox-comment-btn lightbox-comment-send"
              onclick={sendComment}
              disabled={!draft.trim() || sending}
              aria-label={$t('lightbox.send')}
            >
              <span class="material-symbols-outlined rtl-mirror" aria-hidden="true">send</span>
            </button>
          </div>
        </div>
      {/if}
    </aside>
  {/if}
</div>

<style>
  .lightbox {
    position: fixed;
    inset: 0;
    background: var(--scrim-strong);
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
    z-index: 10000;
    display: flex;
    align-items: center;
    justify-content: center;
    animation: lightbox-fade 0.15s ease;
  }

  @keyframes lightbox-fade {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .lightbox-stage {
    max-width: 100vw;
    max-height: 100vh;
    max-height: 100dvh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 40px;
  }

  .lightbox-stage-zoomed {
    overflow: auto;
    cursor: zoom-out;
    padding: 0;
    align-items: flex-start;
  }

  .lightbox-img {
    max-width: calc(100vw - 80px);
    max-height: calc(100vh - 80px);
    max-height: calc(100dvh - 80px);
    object-fit: contain;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5);
    user-select: none;
    cursor: zoom-in;
  }

  .lightbox-img-zoomed {
    max-width: none;
    max-height: none;
    cursor: zoom-out;
  }

  .lightbox-tools-left {
    position: fixed;
    top: 16px;
    left: 16px;
    display: flex;
    gap: 8px;
    z-index: 2;
  }

  .lightbox-close {
    position: fixed;
    top: 16px;
    right: 16px;
    z-index: 2;
  }

  .lightbox-btn {
    width: 40px;
    height: 40px;
    border-radius: 9999px;
    border: none;
    background: rgba(0, 0, 0, 0.55);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: background 0.15s ease, transform 0.15s ease;
  }

  .lightbox-btn:hover {
    background: rgba(0, 0, 0, 0.8);
  }

  .lightbox-btn:active {
    transform: scale(0.96);
  }

  .lightbox-btn :global(.material-symbols-outlined) {
    font-size: 22px;
  }

  .lightbox-nav {
    position: fixed;
    top: 50%;
    transform: translateY(-50%);
    width: 48px;
    height: 48px;
    border-radius: 9999px;
    border: none;
    background: rgba(0, 0, 0, 0.55);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    z-index: 2;
  }

  .lightbox-nav:hover {
    background: rgba(0, 0, 0, 0.8);
  }

  .lightbox-nav-prev { inset-inline-start: 16px; }
  .lightbox-nav-next { inset-inline-end: 16px; }

  .lightbox-nav :global(.material-symbols-outlined) {
    font-size: 28px;
  }

  .lightbox-counter {
    position: fixed;
    bottom: 20px;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(0, 0, 0, 0.6);
    color: #fff;
    padding: 6px 12px;
    border-radius: 9999px;
    font-size: 0.8rem;
    font-variant-numeric: tabular-nums;
    z-index: 2;
  }

  /* Heart button + picker. Wrap so hover-into-picker doesn't trigger
     the leave timeout on the button. */
  .lightbox-react-wrap {
    position: relative;
  }

  .lightbox-btn-react {
    width: auto;
    min-width: 40px;
    padding-inline: 12px;
    gap: 6px;
  }

  .lightbox-btn-reacted {
    color: var(--color-danger, #f0506e);
  }

  .lightbox-btn-reacted :global(.material-symbols-outlined) {
    font-variation-settings: 'FILL' 1;
  }

  .lightbox-react-count {
    font-size: 0.85rem;
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  .lightbox-react-emoji {
    font-size: 22px;
    line-height: 1;
  }

  .lightbox-react-img {
    width: 22px;
    height: 22px;
    object-fit: contain;
  }

  /* Picker pops down beneath the heart button (the lightbox tools live
     at the top-left of the viewport, so dropping is the only direction
     with room). */
  /* The toolbar is pinned to the physical left edge in every locale, so the
     picker opens rightward from it with a physical `left` — with
     `inset-inline-start` an RTL page anchored it on the button's right edge
     and it ran off the left side of the screen. */
  .lightbox-picker-anchor {
    position: absolute;
    inset-block-start: calc(100% + 8px);
    left: 0;
    max-width: calc(100vw - 32px);
    z-index: 4;
  }

  /* Double-tap heart burst — pops above the image, fades out fast. */
  .lightbox-burst {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
    z-index: 3;
    animation: lightbox-burst 0.85s cubic-bezier(0.22, 1, 0.36, 1) forwards;
  }

  .lightbox-burst :global(.material-symbols-outlined) {
    font-size: 140px;
    color: rgba(255, 255, 255, 0.95);
    text-shadow: 0 6px 30px rgba(0, 0, 0, 0.5);
    font-variation-settings: 'FILL' 1;
  }

  .lightbox-burst-emoji {
    font-size: 140px;
    line-height: 1;
    text-shadow: 0 6px 30px rgba(0, 0, 0, 0.5);
  }

  .lightbox-burst-img {
    width: 140px;
    height: 140px;
    object-fit: contain;
    filter: drop-shadow(0 6px 30px rgba(0, 0, 0, 0.5));
  }

  @keyframes lightbox-burst {
    0%   { opacity: 0; transform: scale(0.4); }
    25%  { opacity: 1; transform: scale(1.15); }
    60%  { opacity: 1; transform: scale(1); }
    100% { opacity: 0; transform: scale(0.95); }
  }

  /* Per-image replies sidebar — only mounted when there's something
     to show, so we don't carve out space when an image has no
     image-pinned replies. Pinned to the trailing edge of the
     viewport with a subtle slide-in. */
  .lightbox-sidebar {
    position: fixed;
    inset-block: 0;
    inset-inline-end: 0;
    width: min(360px, 90vw);
    background: rgba(20, 20, 22, 0.92);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    border-inline-start: 1px solid rgba(255, 255, 255, 0.08);
    color: #f3f3f5;
    display: flex;
    flex-direction: column;
    z-index: 3;
    animation: lightbox-sidebar-in 220ms cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes lightbox-sidebar-in {
    from { transform: translateX(100%); opacity: 0; }
    to   { transform: translateX(0); opacity: 1; }
  }

  /* RTL: panel slides in from the inline-start edge. */
  :global([dir="rtl"]) .lightbox-sidebar {
    animation-name: lightbox-sidebar-in-rtl;
  }

  @keyframes lightbox-sidebar-in-rtl {
    from { transform: translateX(-100%); opacity: 0; }
    to   { transform: translateX(0); opacity: 1; }
  }

  .lightbox-sidebar-header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 16px 18px;
    font-size: 0.875rem;
    font-weight: 600;
    border-block-end: 1px solid rgba(255, 255, 255, 0.08);
  }

  .lightbox-sidebar-header :global(.material-symbols-outlined),
  .sidebar-header-icon {
    font-size: 18px;
    opacity: 0.85;
  }

  .lightbox-reply-list {
    list-style: none;
    margin: 0;
    padding: 8px 0;
    overflow-y: auto;
    flex: 1;
  }

  .lightbox-reply {
    display: flex;
    gap: 10px;
    width: 100%;
    padding: 10px 16px;
    background: none;
    border: 0;
    color: inherit;
    text-align: start;
    cursor: pointer;
    font: inherit;
    transition: background 120ms ease;
  }

  .lightbox-reply:hover,
  .lightbox-reply:focus-visible {
    background: rgba(255, 255, 255, 0.06);
    outline: none;
  }

  .lightbox-reply-avatar {
    width: 32px;
    height: 32px;
    border-radius: 9999px;
    object-fit: cover;
    flex-shrink: 0;
  }

  .lightbox-reply-body {
    min-width: 0;
    flex: 1;
  }

  .lightbox-reply-meta {
    display: flex;
    align-items: baseline;
    gap: 8px;
    margin-block-end: 2px;
  }

  .lightbox-reply-name {
    font-size: 0.85rem;
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .lightbox-reply-time {
    font-size: 0.7rem;
    color: rgba(255, 255, 255, 0.6);
  }

  .lightbox-reply-text {
    font-size: 0.85rem;
    line-height: 1.4;
    color: rgba(255, 255, 255, 0.9);
    margin: 0;
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 4;
    -webkit-box-orient: vertical;
    word-break: break-word;
  }

  .lightbox-reply-text :global(a) {
    color: #9bd1ff;
  }

  .lightbox-sidebar-title {
    flex: 1;
    min-width: 0;
  }

  .lightbox-sidebar-close {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: transparent;
    color: inherit;
    cursor: pointer;
  }

  .lightbox-sidebar-close[hidden] {
    display: none;
  }

  .lightbox-comment {
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 10px 12px calc(12px + env(safe-area-inset-bottom, 0px));
    border-block-start: 1px solid rgba(255, 255, 255, 0.08);
  }

  .lightbox-comment-error {
    margin: 0;
    font-size: 0.75rem;
    color: #ff8a9b;
  }

  .lightbox-comment-row {
    display: flex;
    align-items: flex-end;
    gap: 6px;
  }

  .lightbox-comment-input {
    flex: 1;
    min-width: 0;
    min-height: 38px;
    max-height: 120px;
    padding: 8px 14px;
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 19px;
    background: rgba(255, 255, 255, 0.06);
    color: #f3f3f5;
    font: inherit;
    /* 16px stops iOS from zooming the page on focus. */
    font-size: 16px;
    line-height: 1.35;
    resize: none;
    outline: none;
    unicode-bidi: plaintext;
  }

  .lightbox-comment-input:focus {
    border-color: rgba(255, 255, 255, 0.4);
  }

  .lightbox-comment-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    width: 38px;
    height: 38px;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.1);
    color: #fff;
    cursor: pointer;
  }

  .lightbox-comment-send {
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
  }

  .lightbox-comment-btn:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .lightbox-comment-btn :global(.material-symbols-outlined) {
    font-size: 20px;
  }

  /* With the panel open the image must fit beside (wide screens) or above
     (phones) it, whatever its size or proportions — never under the panel
     or past the screen edge. The lightbox reserves the panel's space and
     the image is capped to what is left. */
  @media (min-width: 769px) {
    :global(.lightbox:has(.lightbox-sidebar)) {
      padding-inline-end: min(360px, 90vw);
    }

    :global(.lightbox:has(.lightbox-sidebar)) .lightbox-stage {
      max-width: calc(100vw - min(360px, 90vw));
    }

    :global(.lightbox:has(.lightbox-sidebar)) .lightbox-img:not(.lightbox-img-zoomed) {
      max-width: calc(100vw - min(360px, 90vw) - 80px);
    }

    :global(.lightbox:has(.lightbox-sidebar)) .lightbox-nav-next {
      inset-inline-end: calc(min(360px, 90vw) + 16px);
    }
  }

  /* Phones: the panel is a bottom sheet over the lower part of the screen;
     the image fits in the part above it. */
  @media (max-width: 768px) {
    .lightbox-sidebar {
      inset-block: auto 0;
      inset-inline: 0;
      width: auto;
      height: 46vh;
      height: 46dvh;
      border-inline-start: none;
      border-block-start: 1px solid rgba(255, 255, 255, 0.1);
      border-start-start-radius: 16px;
      border-start-end-radius: 16px;
      animation-name: lightbox-sidebar-up;
    }

    :global([dir="rtl"]) .lightbox-sidebar {
      animation-name: lightbox-sidebar-up;
    }

    :global(.lightbox:has(.lightbox-sidebar)) {
      align-items: flex-start;
      padding-block-end: 46dvh;
    }

    :global(.lightbox:has(.lightbox-sidebar)) .lightbox-stage {
      width: 100%;
      height: 54vh;
      height: 54dvh;
      padding: 64px 12px 12px;
    }

    :global(.lightbox:has(.lightbox-sidebar)) .lightbox-img:not(.lightbox-img-zoomed) {
      max-width: calc(100vw - 24px);
      max-height: calc(54dvh - 76px);
    }

    :global(.lightbox:has(.lightbox-sidebar)) .lightbox-nav {
      top: 27dvh;
    }

    :global(.lightbox:has(.lightbox-sidebar)) .lightbox-counter {
      bottom: calc(46dvh + 12px);
    }
  }

  @keyframes lightbox-sidebar-up {
    from { transform: translateY(100%); opacity: 0; }
    to   { transform: translateY(0); opacity: 1; }
  }
</style>

<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { goto } from '$app/navigation';
  import ReactionPicker from '$lib/components/post/ReactionPicker.svelte';
  import { premiumCatalog, ensurePremiumCatalog } from '$lib/stores/reaction-catalog.js';
  import { getPostContext } from '$lib/api/statuses.js';
  import type { Post } from '$lib/api/types.js';
  import { relativeTime } from '$lib/utils/time.js';

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
  let showSidebar = $derived(currentReplies.length > 0);

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
    if (e.key === 'Escape') close();
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
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', handleKey);
    window.addEventListener('new-post', handleNewReply);
    return () => {
      document.body.style.overflow = prevOverflow;
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
    {#if onreply && current?.id}
      <button
        type="button"
        class="lightbox-btn"
        onclick={() => onreply!(current.id!, index + 1)}
        aria-label="Reply to this image"
        title="Reply to this image"
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
        <span>{currentReplies.length} {currentReplies.length === 1 ? 'reply' : 'replies'} on this image</span>
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
  .lightbox-picker-anchor {
    position: absolute;
    inset-block-start: calc(100% + 8px);
    inset-inline-start: 0;
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

  /* When the sidebar is open, give the stage room so the image
     centres in the remaining space rather than under the panel. */
  :global(.lightbox:has(.lightbox-sidebar)) .lightbox-stage,
  :global(.lightbox:has(.lightbox-sidebar)) .lightbox-img {
    max-width: calc(100vw - min(360px, 90vw) - 80px);
  }
</style>

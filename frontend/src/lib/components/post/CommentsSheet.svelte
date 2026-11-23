<script lang="ts">
  // One place to read a post's comments and write one. The comment button on
  // any post (PostActions) dispatches `open-comments { post }`; this sheet —
  // mounted once in the (app) layout — loads the thread and keeps a comment
  // field pinned to its bottom, so the conversation stays in view while
  // writing. It slides up from the bottom on phones and is a centred dialog
  // on wider screens. The full composer stays one tap away for comments that
  // need media or formatting.
  //
  // Opening pushes a shallow-routing entry (`page.state.commentsSheet`) so
  // the device Back button closes the sheet instead of leaving the page — the
  // same pattern as the mobile More sheet.
  import { onMount, tick } from 'svelte';
  import { page } from '$app/state';
  import { pushState } from '$app/navigation';
  import type { Post } from '$lib/api/types.js';
  import { getPostContext, createPost } from '$lib/api/statuses.js';
  import { ApiError } from '$lib/api/client.js';
  import ThreadedReplies from './ThreadedReplies.svelte';
  import EmojiPicker from './EmojiPicker.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import { currentUser } from '$lib/stores/auth.js';
  import { t } from '$lib/stores/i18n.js';
  import { tError } from '$lib/utils/i18n.js';
  import { lockScroll } from '$lib/utils/scroll-lock.js';
  import { markSeen } from '$lib/utils/seen-posts.js';

  let post = $state<Post | null>(null);
  let descendants = $state<Post[]>([]);
  let loading = $state(false);
  let loadError = $state(false);

  // The comment being answered; null = a comment on the post itself.
  let replyTarget = $state<Post | null>(null);
  let draft = $state('');
  let sending = $state(false);
  let sendError = $state('');
  let showEmoji = $state(false);

  let inputEl: HTMLTextAreaElement | undefined = $state();
  let emojiBtnEl: HTMLButtonElement | undefined = $state();
  let bodyEl: HTMLDivElement | undefined = $state();

  let open = $derived(page.state.commentsSheet === true && post !== null);

  function authorName(p: Post): string {
    return p.account?.display_name || p.account?.acct || p.account?.handle || '';
  }

  async function load(target: Post) {
    loading = true;
    loadError = false;
    descendants = [];
    try {
      const context = await getPostContext(target.id);
      // Ignore a response for a post the sheet has since moved away from.
      if (post?.id === target.id) descendants = context.descendants ?? [];
    } catch {
      if (post?.id === target.id) loadError = true;
    } finally {
      if (post?.id === target.id) loading = false;
    }
  }

  async function focusInput() {
    await tick();
    inputEl?.focus();
  }

  function handleOpen(e: Event) {
    const target = (e as CustomEvent<{ post?: Post }>).detail?.post;
    if (!target) return;
    // "Reply" on a comment inside the open sheet answers that comment here.
    if (open && post && (target.id === post.id || descendants.some((d) => d.id === target.id))) {
      replyTarget = target.id === post.id ? null : target;
      focusInput();
      return;
    }
    // History entry first: the reset effect below clears `post` whenever the
    // entry is missing, so it must already exist when `post` is set.
    if (!page.state.commentsSheet) pushState('', { commentsSheet: true });
    post = target;
    replyTarget = null;
    draft = '';
    sendError = '';
    showEmoji = false;
    load(target);
  }

  function close() {
    showEmoji = false;
    if (page.state.commentsSheet) history.back();
  }

  // Back button / history moved off the sheet's entry → forget the thread.
  $effect(() => {
    if (!page.state.commentsSheet && post) {
      post = null;
      descendants = [];
      replyTarget = null;
    }
  });

  $effect(() => {
    if (open) return lockScroll();
  });

  // --- Keep the thread in step with the rest of the app --------------------
  function belongsHere(p: Post): boolean {
    if (!post) return false;
    return (
      p.parent_id === post.id ||
      p.root_id === post.id ||
      descendants.some((d) => d.id === p.parent_id)
    );
  }

  function onNewPost(e: Event) {
    const p = (e as CustomEvent<Post>).detail;
    if (!p || !belongsHere(p) || descendants.some((d) => d.id === p.id)) return;
    descendants = [...descendants, p];
    // Bring the new comment into view.
    tick().then(() => {
      bodyEl?.scrollTo({ top: bodyEl.scrollHeight, behavior: 'smooth' });
    });
  }

  function onPostReplace(e: Event) {
    const { oldId, post: real } = (e as CustomEvent<{ oldId: string; post: Post }>).detail ?? {};
    if (!oldId || !real || !descendants.some((d) => d.id === oldId)) return;
    descendants = descendants.filter((d) => d.id !== real.id).map((d) => (d.id === oldId ? real : d));
  }

  function onPostDeleted(e: Event) {
    const id = (e as CustomEvent<{ id: string }>).detail?.id;
    if (id && descendants.some((d) => d.id === id)) {
      descendants = descendants.filter((d) => d.id !== id);
    }
  }

  onMount(() => {
    window.addEventListener('open-comments', handleOpen);
    window.addEventListener('new-post', onNewPost);
    window.addEventListener('post-replace', onPostReplace);
    window.addEventListener('post-deleted', onPostDeleted);
    return () => {
      window.removeEventListener('open-comments', handleOpen);
      window.removeEventListener('new-post', onNewPost);
      window.removeEventListener('post-replace', onPostReplace);
      window.removeEventListener('post-deleted', onPostDeleted);
    };
  });

  // --- Writing --------------------------------------------------------------
  function autosize() {
    if (!inputEl) return;
    inputEl.style.height = 'auto';
    inputEl.style.height = `${Math.min(inputEl.scrollHeight, 140)}px`;
  }

  function onInputKey(e: KeyboardEvent) {
    // Enter sends on a keyboard; Shift+Enter (and every phone keyboard's
    // return key on touch devices) keeps a new line.
    const touch = window.matchMedia('(pointer: coarse)').matches;
    if (e.key === 'Enter' && !e.shiftKey && !touch) {
      e.preventDefault();
      send();
    } else if (e.key === 'Escape' && replyTarget) {
      e.preventDefault();
      replyTarget = null;
    }
  }

  function insertEmoji(text: string) {
    const el = inputEl;
    if (!el) {
      draft += text;
      return;
    }
    const start = el.selectionStart ?? draft.length;
    const end = el.selectionEnd ?? draft.length;
    draft = draft.slice(0, start) + text + draft.slice(end);
    tick().then(() => {
      el.focus();
      el.setSelectionRange(start + text.length, start + text.length);
      autosize();
    });
  }

  function errorMessage(err: unknown): string {
    const code = err instanceof ApiError ? (err.body as { error?: string } | null)?.error : undefined;
    if (code?.startsWith('trust.')) return tError(code);
    return $t('composer.publish_failed');
  }

  function bumpCounts(parentId: string, rootId: string | null, delta: number) {
    window.dispatchEvent(new CustomEvent('reply-count-update', { detail: { postId: parentId, delta } }));
    if (rootId) {
      window.dispatchEvent(new CustomEvent('reply-count-update', { detail: { postId: rootId, delta } }));
    }
  }

  async function send() {
    const text = draft.trim();
    const me = $currentUser;
    if (!text || !post || !me || sending) return;
    const parent = replyTarget ?? post;
    // A reply keeps its parent's audience — a public reply to a direct post
    // would leak the thread (same rule as the full composer).
    const visibility: Post['visibility'] =
      parent.visibility === 'followers' || parent.visibility === 'direct'
        ? parent.visibility
        : 'public';
    // A root's counter covers its whole thread, so a deeper reply bumps it too.
    const rootId = parent.root_id && parent.root_id !== parent.id ? parent.root_id : null;

    const optimisticId = `optimistic-${Date.now()}`;
    const escaped = text.replace(/&/g, '&amp;').replace(/</g, '&lt;');
    const optimistic = {
      id: optimisticId,
      type: 'text',
      post_type: 'text',
      content: text,
      content_html: `<p>${escaped.replace(/\n\n+/g, '</p><p>').replace(/\n/g, '<br>')}</p>`,
      visibility,
      sensitive: false,
      spoiler_text: null,
      language: null,
      reply_count: 0,
      boost_count: 0,
      reaction_count: 0,
      is_pinned: false,
      is_boosted: false,
      is_bookmarked: false,
      is_muted: false,
      current_user_reaction: null,
      created_at: new Date().toISOString(),
      edited_at: null,
      expires_at: null,
      account: me,
      parent_id: parent.id,
      root_id: rootId ?? post.id,
      in_reply_to_account_id: null,
      quote: null,
      card: null,
      mentions: [],
      tags: [],
      emojis: [],
      reactions: [],
      poll: null,
      media_attachments: [],
      uri: '',
      url: '',
      pending: true,
    } as unknown as Post;

    sending = true;
    sendError = '';
    const keptTarget = replyTarget;
    draft = '';
    replyTarget = null;
    tick().then(autosize);

    window.dispatchEvent(new CustomEvent('new-post', { detail: optimistic }));
    markSeen(parent.id);
    bumpCounts(parent.id, rootId, 1);

    try {
      const real = await createPost({ content: text, visibility, parent_id: parent.id });
      window.dispatchEvent(new CustomEvent('post-replace', { detail: { oldId: optimisticId, post: real } }));
    } catch (err) {
      // Nothing written is lost: put it back and say why.
      window.dispatchEvent(new CustomEvent('post-deleted', { detail: { id: optimisticId } }));
      bumpCounts(parent.id, rootId, -1);
      draft = text;
      replyTarget = keptTarget;
      sendError = errorMessage(err);
      tick().then(autosize);
    } finally {
      sending = false;
    }
  }

  // Media, formatting, polls… → the full composer, with what was typed.
  function openFullComposer() {
    if (!post) return;
    const replyTo = replyTarget ?? post;
    const prefill = draft;
    close();
    window.dispatchEvent(
      new CustomEvent('open-composer', { detail: { replyTo, ...(prefill ? { prefill } : {}) } }),
    );
  }

  // --- Phones: follow the on-screen keyboard, swipe down to close ----------
  // Browsers that overlay the keyboard (instead of resizing the page) would
  // hide a bottom-pinned field behind it; lift the sheet by the covered part.
  let keyboardInset = $state(0);
  $effect(() => {
    if (!open) return;
    const vv = window.visualViewport;
    if (!vv) return;
    const update = () => {
      keyboardInset = Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop));
    };
    update();
    vv.addEventListener('resize', update);
    vv.addEventListener('scroll', update);
    return () => {
      vv.removeEventListener('resize', update);
      vv.removeEventListener('scroll', update);
      keyboardInset = 0;
    };
  });

  const DISMISS_PX = 80;
  let dragY = $state(0);
  let dragging = $state(false);
  let sheetEl: HTMLDivElement | undefined = $state();

  $effect(() => {
    const el = sheetEl;
    if (!el) return;
    let startY = 0;
    let tracking = false;

    const onStart = (e: TouchEvent) => {
      const target = e.target as HTMLElement;
      // Not from the writing area, and only when the list is at its top, so a
      // downward swipe inside a scrolled list still scrolls it.
      if (target.closest('.cs-footer') || e.touches.length !== 1) {
        tracking = false;
        return;
      }
      tracking = (bodyEl?.scrollTop ?? 0) <= 0 || !!target.closest('.cs-header');
      startY = e.touches[0].clientY;
    };
    const onMove = (e: TouchEvent) => {
      if (!tracking) return;
      const dy = e.touches[0].clientY - startY;
      if (dy <= 0 && !dragging) {
        tracking = false;
        return;
      }
      dragging = true;
      dragY = Math.max(0, dy);
      if (e.cancelable) e.preventDefault();
    };
    const onEnd = () => {
      if (dragging && dragY > DISMISS_PX) close();
      tracking = false;
      dragging = false;
      dragY = 0;
    };

    el.addEventListener('touchstart', onStart, { passive: true });
    el.addEventListener('touchmove', onMove, { passive: false });
    el.addEventListener('touchend', onEnd);
    el.addEventListener('touchcancel', onEnd);
    return () => {
      el.removeEventListener('touchstart', onStart);
      el.removeEventListener('touchmove', onMove);
      el.removeEventListener('touchend', onEnd);
      el.removeEventListener('touchcancel', onEnd);
    };
  });

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape' && !showEmoji && !replyTarget) close();
  }

  let count = $derived(descendants.length);
</script>

<svelte:window onkeydown={open ? onKey : undefined} />

{#if open && post}
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="cs-backdrop" onclick={close}></div>

  <div
    bind:this={sheetEl}
    class="cs-sheet"
    class:cs-dragging={dragging}
    role="dialog"
    aria-modal="true"
    aria-labelledby="cs-title"
    style:--cs-kb="{keyboardInset}px"
    style:transform={dragY ? `translateY(${dragY}px)` : undefined}
  >
    <div class="cs-header">
      <div class="cs-handle" aria-hidden="true"></div>
      <div class="cs-titlebar">
        <h2 id="cs-title" class="cs-title">
          {$t('comments.title')}
          {#if count > 0}<span class="cs-count" dir="ltr">{count}</span>{/if}
        </h2>
        <button type="button" class="cs-icon-btn" onclick={close} aria-label={$t('comments.close')}>
          <span class="material-symbols-outlined" aria-hidden="true">close</span>
        </button>
      </div>
    </div>

    <div class="cs-body" bind:this={bodyEl}>
      {#if loading}
        <div class="cs-status" role="status">
          <span class="cs-spinner" aria-hidden="true"></span>
          {$t('comments.loading')}
        </div>
      {:else if loadError}
        <div class="cs-status">
          {$t('comments.load_failed')}
          <button type="button" class="cs-retry" onclick={() => post && load(post)}>
            {$t('comments.retry')}
          </button>
        </div>
      {:else if descendants.length === 0}
        <div class="cs-status cs-empty">
          <span class="material-symbols-outlined" aria-hidden="true">forum</span>
          <p>{$t('comments.empty')}</p>
        </div>
      {:else}
        <ThreadedReplies {descendants} rootPostId={post.id} rootAccountId={post.account.id} />
      {/if}
    </div>

    {#if $currentUser}
      <div class="cs-footer">
        {#if replyTarget}
          <div class="cs-replying" role="status">
            <span class="material-symbols-outlined rtl-mirror" aria-hidden="true">reply</span>
            <span class="cs-replying-text">
              {$t('comments.replying_to', { name: authorName(replyTarget) })}
            </span>
            <button
              type="button"
              class="cs-icon-btn cs-icon-btn-sm"
              onclick={() => (replyTarget = null)}
              aria-label={$t('comments.cancel_reply')}
            >
              <span class="material-symbols-outlined" aria-hidden="true">close</span>
            </button>
          </div>
        {/if}
        {#if sendError}
          <p class="cs-error" role="alert">{sendError}</p>
        {/if}
        <div class="cs-input-row">
          <Avatar
            src={$currentUser.avatar_url ?? null}
            name={$currentUser.display_name || $currentUser.handle || ''}
            size="sm"
          />
          <div class="cs-field">
            <textarea
              bind:this={inputEl}
              bind:value={draft}
              class="cs-input"
              rows="1"
              dir="auto"
              placeholder={$t('comments.placeholder')}
              aria-label={$t('comments.placeholder')}
              oninput={autosize}
              onkeydown={onInputKey}
            ></textarea>
            <button
              bind:this={emojiBtnEl}
              type="button"
              class="cs-icon-btn cs-icon-btn-sm"
              onclick={() => (showEmoji = !showEmoji)}
              aria-label={$t('comments.emoji')}
              aria-expanded={showEmoji}
            >
              <span class="material-symbols-outlined" aria-hidden="true">mood</span>
            </button>
            <button
              type="button"
              class="cs-icon-btn cs-icon-btn-sm"
              onclick={openFullComposer}
              aria-label={$t('comments.full_composer')}
              title={$t('comments.full_composer')}
            >
              <span class="material-symbols-outlined" aria-hidden="true">open_in_full</span>
            </button>
          </div>
          <button
            type="button"
            class="cs-send"
            onclick={send}
            disabled={!draft.trim() || sending}
            aria-label={$t('comments.send')}
          >
            <span class="material-symbols-outlined rtl-mirror" aria-hidden="true">send</span>
          </button>
        </div>
        {#if showEmoji}
          <EmojiPicker
            anchor={emojiBtnEl}
            onselect={insertEmoji}
            onclose={() => (showEmoji = false)}
          />
        {/if}
      </div>
    {/if}
  </div>
{/if}

<style>
  /* Above the header (z 50) so the sheet owns the screen while open. */
  .cs-backdrop {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    z-index: 51;
    animation: cs-fade 0.15s ease;
  }

  .cs-sheet {
    position: fixed;
    z-index: 52;
    display: flex;
    flex-direction: column;
    background: var(--color-surface-raised, var(--color-surface));
    box-shadow: var(--shadow-lg);
    overscroll-behavior: contain;
    transition: transform 0.2s ease;
  }

  .cs-sheet.cs-dragging {
    transition: none;
  }

  /* Phones and narrow screens: a sheet from the bottom edge. */
  @media (max-width: 768px) {
    .cs-sheet {
      inset-inline: 0;
      bottom: var(--cs-kb, 0px);
      height: 88vh;
      height: calc(88dvh - var(--cs-kb, 0px));
      border-start-start-radius: 18px;
      border-start-end-radius: 18px;
      padding-bottom: env(safe-area-inset-bottom, 0px);
      animation: cs-slide-up 0.24s cubic-bezier(0.22, 1, 0.36, 1);
    }
  }

  /* Wider screens: a centred dialog. Physical left (direction-neutral
     centring — see StreamPlayer's .tap-glyph). */
  @media (min-width: 769px) {
    .cs-sheet {
      top: 50%;
      left: 50%;
      translate: -50% -50%;
      width: min(640px, calc(100vw - 48px));
      height: 80vh;
      height: 80dvh;
      border: 1px solid var(--color-border);
      border-radius: 16px;
      animation: cs-pop 0.18s ease;
    }

    .cs-handle {
      display: none;
    }
  }

  @keyframes cs-fade {
    from { opacity: 0; }
  }

  @keyframes cs-slide-up {
    from { transform: translateY(100%); }
  }

  @keyframes cs-pop {
    from { opacity: 0; scale: 0.97; }
  }

  .cs-header {
    flex-shrink: 0;
    border-block-end: 1px solid var(--color-border);
    touch-action: none;
  }

  .cs-handle {
    width: 36px;
    height: 4px;
    margin: var(--space-2) auto 0;
    border-radius: 999px;
    background: var(--color-border);
  }

  .cs-titlebar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3) var(--space-2) var(--space-4);
  }

  .cs-title {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin: 0;
    font-size: var(--text-base);
    font-weight: 700;
    color: var(--color-text);
  }

  .cs-count {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
  }

  .cs-icon-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    width: 40px;
    height: 40px;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: transparent;
    color: var(--color-text-secondary);
    cursor: pointer;
  }

  .cs-icon-btn:hover {
    background: var(--color-surface-hover, var(--color-surface));
    color: var(--color-text);
  }

  .cs-icon-btn-sm {
    width: 34px;
    height: 34px;
  }

  .cs-icon-btn-sm .material-symbols-outlined {
    font-size: 20px;
  }

  .cs-body {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overflow-x: hidden;
    overscroll-behavior: contain;
    padding: var(--space-2) var(--space-3);
  }

  .cs-status {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    min-height: 160px;
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    text-align: center;
  }

  .cs-empty .material-symbols-outlined {
    font-size: 40px;
    opacity: 0.5;
  }

  .cs-empty p {
    margin: 0;
  }

  .cs-spinner {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    border: 3px solid var(--color-border);
    border-top-color: var(--color-primary);
    animation: cs-spin 0.8s linear infinite;
  }

  @keyframes cs-spin {
    to { transform: rotate(360deg); }
  }

  .cs-retry {
    padding: 6px 16px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    background: transparent;
    color: var(--color-text);
    cursor: pointer;
  }

  .cs-footer {
    position: relative;
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3) var(--space-3);
    border-block-start: 1px solid var(--color-border);
    background: inherit;
  }

  .cs-replying {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding-inline-start: var(--space-2);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .cs-replying .material-symbols-outlined {
    font-size: 16px;
    color: var(--color-primary);
  }

  .cs-replying-text {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .cs-error {
    margin: 0;
    font-size: var(--text-xs);
    color: var(--color-danger);
  }

  .cs-input-row {
    display: flex;
    align-items: flex-end;
    gap: var(--space-2);
  }

  .cs-field {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: flex-end;
    gap: 2px;
    padding: 2px 4px 2px var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: 20px;
    background: var(--color-surface);
  }

  .cs-field:focus-within {
    border-color: var(--color-primary);
  }

  .cs-input {
    flex: 1;
    min-width: 0;
    min-height: 34px;
    max-height: 140px;
    padding: 7px 0;
    border: none;
    outline: none;
    resize: none;
    background: transparent;
    color: var(--color-text);
    font: inherit;
    /* 16px stops iOS from zooming the page on focus. */
    font-size: 16px;
    line-height: 1.35;
    text-align: start;
    unicode-bidi: plaintext;
  }

  .cs-send {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    width: 40px;
    height: 40px;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
    cursor: pointer;
    transition: opacity 0.15s ease;
  }

  .cs-send:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .cs-send .material-symbols-outlined {
    font-size: 20px;
  }

  @media (prefers-reduced-motion: reduce) {
    .cs-sheet,
    .cs-backdrop {
      animation: none;
    }
  }
</style>

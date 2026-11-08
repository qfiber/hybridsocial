<script lang="ts">
  import { api } from '$lib/api/client.js';
  import { authStore } from '$lib/stores/auth.js';
  import { get } from 'svelte/store';
  import type { Identity, Relationship } from '$lib/api/types.js';
  import AccountTypeIndicator from '$lib/components/ui/AccountTypeIndicator.svelte';
  import DisplayName from '$lib/components/DisplayName.svelte';
  import {
    follow as apiFollow,
    unfollow as apiUnfollow,
    mute as apiMute,
    unmute as apiUnmute,
    block as apiBlock,
    unblock as apiUnblock,
    getRelationship,
  } from '$lib/api/accounts.js';

  let {
    handle,
    children,
  }: {
    handle: string;
    children: any;
  } = $props();

  let visible = $state(false);
  let account = $state<Identity | null>(null);
  let relationship = $state<Relationship | null>(null);
  let loading = $state(false);
  let openBelow = $state(false);
  let busy = $state<'follow' | 'mute' | 'block' | null>(null);
  let hoverTimer: ReturnType<typeof setTimeout> | null = null;
  let hideTimer: ReturnType<typeof setTimeout> | null = null;
  let cardEl: HTMLDivElement | undefined = $state();
  let triggerEl: HTMLSpanElement | undefined = $state();

  async function fetchAccount() {
    if (account || loading) return;
    loading = true;
    try {
      account = await api.get<Identity>(`/api/v1/accounts/lookup`, { handle });
      // Fetch the viewer↔account relationship in parallel with what
      // already loaded so the action buttons reflect actual state
      // (already-following, muted, blocked) before the user clicks.
      const me = get(authStore).user;
      if (account && me && me.id !== account.id) {
        try {
          relationship = await getRelationship(account.id);
        } catch { /* leave relationship null */ }
      }
    } catch { /* */ }
    finally { loading = false; }
  }

  function show() {
    if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
    hoverTimer = setTimeout(() => {
      if (triggerEl) {
        const rect = triggerEl.getBoundingClientRect();
        openBelow = rect.top < 320;
      }
      visible = true;
      fetchAccount();
    }, 400);
  }

  function hide() {
    if (hoverTimer) { clearTimeout(hoverTimer); hoverTimer = null; }
    hideTimer = setTimeout(() => { visible = false; }, 200);
  }

  function cancelHide() {
    if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
  }

  // ── Touch ──
  // Hover never happens on touch, so the card's Follow/Mute/Block were
  // unreachable there. A tap still opens the profile (the name is a link);
  // a long-press opens the card instead. The browser's emulated
  // mouseenter/focus that follow a tap are ignored so the card doesn't
  // flash on the way to the profile.
  const LONG_PRESS_MS = 500;
  const MOVE_TOLERANCE_PX = 10;
  let pressTimer: ReturnType<typeof setTimeout> | null = null;
  let pressStart = { x: 0, y: 0 };
  let lastTouchAt = 0;
  let openedByTouch = $state(false);
  let suppressClick = false;

  function cancelPress() {
    if (pressTimer) { clearTimeout(pressTimer); pressTimer = null; }
  }

  function handlePointerDown(e: PointerEvent) {
    if (e.pointerType === 'mouse') return;
    // A long-press that ended in Android's context menu never delivers its
    // click, so don't let that stale flag swallow this new tap.
    suppressClick = false;
    lastTouchAt = Date.now();
    pressStart = { x: e.clientX, y: e.clientY };
    cancelPress();
    pressTimer = setTimeout(() => {
      pressTimer = null;
      if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
      if (triggerEl) openBelow = triggerEl.getBoundingClientRect().top < 320;
      openedByTouch = true;
      suppressClick = true;
      visible = true;
      fetchAccount();
      navigator.vibrate?.(10);
    }, LONG_PRESS_MS);
  }

  function handlePointerMove(e: PointerEvent) {
    if (!pressTimer) return;
    if (Math.hypot(e.clientX - pressStart.x, e.clientY - pressStart.y) > MOVE_TOLERANCE_PX) cancelPress();
  }

  // The click that ends a long-press must not follow the name's link.
  function handleClickCapture(e: MouseEvent) {
    if (!suppressClick) return;
    suppressClick = false;
    e.preventDefault();
    e.stopPropagation();
  }

  // Keep Android's link context menu from opening over the card.
  function handleContextMenu(e: Event) {
    if (pressTimer || openedByTouch) e.preventDefault();
  }

  function handlePointerEnter(e: PointerEvent) {
    if (e.pointerType === 'mouse') show();
  }

  function handlePointerLeave(e: PointerEvent) {
    if (e.pointerType === 'mouse') hide();
  }

  function handleFocusIn() {
    // A tap focuses the link too; only keyboard focus should open the card.
    if (Date.now() - lastTouchAt < 1000) return;
    show();
  }

  // A touch-opened card has no mouseleave to close it: close on a tap
  // anywhere outside it instead.
  $effect(() => {
    if (!visible || !openedByTouch) return;
    const onOutside = (e: PointerEvent) => {
      if (cardEl?.contains(e.target as Node)) return;
      visible = false;
      openedByTouch = false;
    };
    document.addEventListener('pointerdown', onOutside, true);
    return () => document.removeEventListener('pointerdown', onOutside, true);
  });

  $effect(() => () => {
    cancelPress();
    if (hoverTimer) clearTimeout(hoverTimer);
    if (hideTimer) clearTimeout(hideTimer);
  });

  let isOwnAccount = $derived(account ? get(authStore).user?.id === account.id : false);

  let isFollowing = $derived(relationship?.following ?? false);
  let isRequested = $derived(relationship?.requested ?? false);
  let isMuting = $derived(relationship?.muting ?? false);
  let isBlocking = $derived(relationship?.blocking ?? false);

  async function handleFollow() {
    if (!account || isOwnAccount || busy) return;
    busy = 'follow';
    const before = relationship;
    try {
      const next = isFollowing || isRequested
        ? await apiUnfollow(account.id)
        : await apiFollow(account.id);
      relationship = next;
      // Best-effort follower count update for visual feedback (the
      // server is the source of truth — if the user reopens the card
      // the next fetch will reconcile).
      if (account) {
        const delta = (next.following ? 1 : 0) - (before?.following ? 1 : 0);
        if (delta !== 0) {
          account = { ...account, followers_count: Math.max(0, (account.followers_count ?? 0) + delta) };
        }
      }
    } catch { /* leave state unchanged */ }
    finally { busy = null; }
  }

  async function handleMute() {
    if (!account || isOwnAccount || busy) return;
    busy = 'mute';
    try {
      relationship = isMuting ? await apiUnmute(account.id) : await apiMute(account.id);
    } catch { /* */ }
    finally { busy = null; }
  }

  async function handleBlock() {
    if (!account || isOwnAccount || busy) return;
    busy = 'block';
    try {
      relationship = isBlocking ? await apiUnblock(account.id) : await apiBlock(account.id);
    } catch { /* */ }
    finally { busy = null; }
  }

  function followIcon() {
    if (isFollowing) return 'how_to_reg';
    if (isRequested) return 'hourglass_empty';
    return 'person_add';
  }

  function followLabel() {
    if (isFollowing) return 'Unfollow';
    if (isRequested) return 'Cancel follow request';
    return 'Follow';
  }
</script>

<span
  class="hover-card-trigger"
  bind:this={triggerEl}
  onpointerenter={handlePointerEnter}
  onpointerleave={handlePointerLeave}
  onpointerdown={handlePointerDown}
  onpointermove={handlePointerMove}
  onpointerup={cancelPress}
  onpointercancel={cancelPress}
  onclickcapture={handleClickCapture}
  oncontextmenu={handleContextMenu}
  onfocusin={handleFocusIn}
  onfocusout={hide}
  role="presentation"
>
  {@render children()}

  {#if visible}
    <div
      class="hover-card"
      class:hover-card-below={openBelow}
      bind:this={cardEl}
      onpointerenter={(e) => { if (e.pointerType === 'mouse') cancelHide(); }}
      onpointerleave={handlePointerLeave}
    >
      {#if loading || !account}
        <div class="hc-loading">
          <div class="hc-skeleton-header"></div>
          <div class="hc-skeleton-body">
            <div class="hc-skeleton-avatar"></div>
            <div class="hc-skeleton-line"></div>
            <div class="hc-skeleton-line short"></div>
          </div>
        </div>
      {:else}
        <!-- The link wraps only the navigable surfaces (header, avatar,
             name, handle, stats, bio). Action buttons live outside so a
             toggle click never bubbles to navigate to the profile. -->
        <a href="/@{account.handle}" class="hc-link" onclick={(e) => e.stopPropagation()}>
          <div class="hc-header" style="background-image: url({account.header_url || '/images/default-cover.svg'})"></div>
          <div class="hc-avatar-row">
            <div class="hc-avatar-wrap">
              <img src={account.avatar_url || '/images/default-avatar.svg'} alt="" class="hc-avatar" />
            </div>
          </div>
        </a>

        <div class="hc-info">
          <div class="hc-name-row">
            <a href="/@{account.handle}" class="hc-name-link" onclick={(e) => e.stopPropagation()}>
              <div class="hc-name"><DisplayName name={account.display_name} fallback={account.handle} emojis={account.emojis} /></div>
              <AccountTypeIndicator account={account} />
            </a>
            {#if !isOwnAccount}
              <div class="hc-actions">
                <button
                  type="button"
                  class="hc-action-btn hc-action-follow"
                  class:hc-action-active={isFollowing || isRequested}
                  title={followLabel()}
                  aria-label={followLabel()}
                  aria-pressed={isFollowing || isRequested}
                  disabled={busy !== null}
                  onclick={handleFollow}
                >
                  <span class="material-symbols-outlined">{followIcon()}</span>
                </button>
                <button
                  type="button"
                  class="hc-action-btn hc-action-mute"
                  class:hc-action-active={isMuting}
                  title={isMuting ? 'Unmute' : 'Mute'}
                  aria-label={isMuting ? 'Unmute' : 'Mute'}
                  aria-pressed={isMuting}
                  disabled={busy !== null}
                  onclick={handleMute}
                >
                  <span class="material-symbols-outlined">{isMuting ? 'volume_up' : 'volume_off'}</span>
                </button>
                <button
                  type="button"
                  class="hc-action-btn hc-action-block"
                  class:hc-action-active={isBlocking}
                  title={isBlocking ? 'Unblock' : 'Block'}
                  aria-label={isBlocking ? 'Unblock' : 'Block'}
                  aria-pressed={isBlocking}
                  disabled={busy !== null}
                  onclick={handleBlock}
                >
                  <span class="material-symbols-outlined">block</span>
                </button>
              </div>
            {/if}
          </div>
          <a href="/@{account.handle}" class="hc-handle-link" onclick={(e) => e.stopPropagation()}>
            <div class="hc-handle">@{account.acct || account.handle}</div>
          </a>

          <div class="hc-stats">
            <span><strong>{account.followers_count ?? 0}</strong> Followers</span>
            <span><strong>{account.following_count ?? 0}</strong> Following</span>
          </div>

          {#if relationship?.followed_by}
            <div class="hc-follows-you">Follows you</div>
          {/if}

          {#if account.bio}
            <div class="hc-bio">{@html account.bio}</div>
          {/if}
        </div>
      {/if}
    </div>
  {/if}
</span>

<style>
  .hover-card-trigger {
    position: relative;
    display: inline;
  }

  /* Long-press opens the card on touch: suppress iOS's link preview
     callout and text selection so they don't compete with it. */
  @media (pointer: coarse) {
    .hover-card-trigger {
      -webkit-touch-callout: none;
      -webkit-user-select: none;
      user-select: none;
    }
  }

  .hover-card {
    position: absolute;
    bottom: 100%;
    inset-inline-start: 0;
    margin-bottom: 8px;
    width: 320px;
    max-width: calc(100vw - 32px);
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 16px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.14);
    z-index: 9000;
    overflow: hidden;
    animation: hc-in-up 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .hover-card-below {
    bottom: auto;
    top: 100%;
    margin-bottom: 0;
    margin-top: 8px;
    animation: hc-in-down 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes hc-in-up {
    from { opacity: 0; transform: translateY(4px) scale(0.97); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }

  @keyframes hc-in-down {
    from { opacity: 0; transform: translateY(-4px) scale(0.97); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }

  .hc-link {
    text-decoration: none;
    color: inherit;
    display: block;
  }

  /* ---- Header ---- */
  .hc-header {
    height: 100px;
    background-size: cover;
    background-position: center;
    position: relative;
  }

  .hc-header-gradient {
    position: absolute;
    inset: 0;
    background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-primary-soft, rgba(108,62,221,0.3)) 100%);
  }

  /* ---- Avatar + Follow row ---- */
  .hc-avatar-row {
    display: flex;
    align-items: flex-end;
    padding: 0 16px;
    margin-top: -28px;
    position: relative;
    z-index: 1;
  }

  .hc-avatar-wrap {
    border: 3px solid var(--color-surface-container-lowest);
    border-radius: 50%;
    background: var(--color-surface-container-lowest);
    line-height: 0;
  }

  .hc-avatar {
    width: 56px;
    height: 56px;
    border-radius: 50%;
    object-fit: cover;
    display: block;
  }

  .hc-avatar-placeholder {
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary);
    color: white;
    font-weight: 700;
    font-size: 1.25rem;
  }

  .hc-actions {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
  }

  .hc-action-btn {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    border: 1px solid var(--color-border);
    background: var(--color-surface-container-lowest);
    color: var(--color-text-secondary);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.15s ease;
  }

  .hc-action-btn .material-symbols-outlined {
    font-size: 16px;
  }

  .hc-action-follow:hover {
    background: var(--color-primary);
    color: var(--color-on-primary);
    border-color: var(--color-primary);
  }

  .hc-action-mute:hover {
    background: var(--color-warning);
    color: white;
    border-color: var(--color-warning);
  }

  .hc-action-block:hover {
    background: var(--color-danger);
    color: white;
    border-color: var(--color-danger);
  }

  /* Active states reflect current relationship — already-following,
     already-muted, already-blocked render filled instead of outlined,
     so the user can tell at a glance the action would *undo* the
     relationship rather than apply it. */
  .hc-action-follow.hc-action-active {
    background: var(--color-primary);
    color: var(--color-on-primary);
    border-color: var(--color-primary);
  }
  .hc-action-mute.hc-action-active {
    background: var(--color-warning);
    color: white;
    border-color: var(--color-warning);
  }
  .hc-action-block.hc-action-active {
    background: var(--color-danger);
    color: white;
    border-color: var(--color-danger);
  }

  .hc-action-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .hc-action-btn:active {
    transform: scale(0.9);
  }

  .hc-name-link,
  .hc-handle-link {
    text-decoration: none;
    color: inherit;
    display: contents;
  }

  .hc-follows-you {
    display: inline-block;
    align-self: flex-start;
    margin-block-end: 6px;
    padding: 1px 6px;
    border-radius: 4px;
    background: var(--color-surface);
    color: var(--color-text-secondary);
    font-size: 0.7rem;
    font-weight: 600;
  }

  /* ---- Info ---- */
  .hc-info {
    padding: 10px 16px 14px;
  }

  .hc-name-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .hc-name {
    font-size: 0.9375rem;
    font-weight: 700;
    color: var(--color-text);
    line-height: 1.3;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .hc-handle {
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
    margin-bottom: 8px;
  }

  .hc-stats {
    display: flex;
    gap: 14px;
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
    margin-bottom: 8px;
  }

  .hc-stats strong {
    color: var(--color-primary);
    font-weight: 700;
  }

  .hc-bio {
    font-size: 0.8125rem;
    color: var(--color-text);
    line-height: 1.5;
    display: -webkit-box;
    -webkit-line-clamp: 3;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .hc-bio :global(p) { margin: 0; }
  .hc-bio :global(a) { color: var(--color-primary); }

  /* ---- Loading skeleton ---- */
  .hc-loading {
    overflow: hidden;
  }

  .hc-skeleton-header {
    height: 100px;
    background: var(--color-surface);
    animation: hc-pulse 1.2s ease-in-out infinite;
  }

  .hc-skeleton-body {
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .hc-skeleton-avatar {
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: var(--color-surface);
    margin-top: -36px;
    animation: hc-pulse 1.2s ease-in-out infinite;
  }

  .hc-skeleton-line {
    height: 12px;
    width: 60%;
    border-radius: 6px;
    background: var(--color-surface);
    animation: hc-pulse 1.2s ease-in-out infinite;
  }

  .hc-skeleton-line.short { width: 35%; }

  @keyframes hc-pulse {
    0%, 100% { opacity: 0.4; }
    50% { opacity: 0.8; }
  }
</style>

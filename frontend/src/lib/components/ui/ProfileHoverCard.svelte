<script lang="ts">
  import { api } from '$lib/api/client.js';
  import { authStore } from '$lib/stores/auth.js';
  import { get } from 'svelte/store';
  import type { Identity } from '$lib/api/types.js';

  let {
    handle,
    children,
  }: {
    handle: string;
    children: any;
  } = $props();

  let visible = $state(false);
  let account = $state<Identity | null>(null);
  let loading = $state(false);
  let openBelow = $state(false);
  let hoverTimer: ReturnType<typeof setTimeout> | null = null;
  let hideTimer: ReturnType<typeof setTimeout> | null = null;
  let cardEl: HTMLDivElement | undefined = $state();
  let triggerEl: HTMLSpanElement | undefined = $state();

  async function fetchAccount() {
    if (account || loading) return;
    loading = true;
    try {
      account = await api.get<Identity>(`/api/v1/accounts/lookup`, { handle });
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

  let isOwnAccount = $derived(account ? get(authStore).user?.id === account.id : false);

  async function handleFollow() {
    if (!account || isOwnAccount) return;
    try {
      await api.post(`/api/v1/accounts/${account.id}/follow`);
      account = { ...account, followers_count: (account.followers_count ?? 0) + 1 } as any;
    } catch { /* */ }
  }

  async function handleMute() {
    if (!account || isOwnAccount) return;
    try {
      await api.post(`/api/v1/accounts/${account.id}/mute`);
    } catch { /* */ }
  }

  async function handleBlock() {
    if (!account || isOwnAccount) return;
    try {
      await api.post(`/api/v1/accounts/${account.id}/block`);
    } catch { /* */ }
  }
</script>

<span
  class="hover-card-trigger"
  bind:this={triggerEl}
  onmouseenter={show}
  onmouseleave={hide}
  onfocusin={show}
  onfocusout={hide}
>
  {@render children()}

  {#if visible}
    <div
      class="hover-card"
      class:hover-card-below={openBelow}
      bind:this={cardEl}
      onmouseenter={cancelHide}
      onmouseleave={hide}
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
        <a href="/@{account.handle}" class="hc-link" onclick={(e) => e.stopPropagation()}>
          <!-- Header banner -->
          <div class="hc-header" style="background-image: url({account.header_url || '/images/default-cover.svg'})"></div>

          <!-- Avatar row -->
          <div class="hc-avatar-row">
            <div class="hc-avatar-wrap">
              <img src={account.avatar_url || '/images/default-avatar.svg'} alt="" class="hc-avatar" />
            </div>
          </div>

          <!-- Info -->
          <div class="hc-info">
            <div class="hc-name-row">
              <div class="hc-name">{account.display_name || account.handle}</div>
              {#if !isOwnAccount}
                <div class="hc-actions">
                  <button
                    type="button"
                    class="hc-action-btn hc-action-follow"
                    title="Follow"
                    onclick={(e) => { e.preventDefault(); e.stopPropagation(); handleFollow(); }}
                  >
                    <span class="material-symbols-outlined">person_add</span>
                  </button>
                  <button
                    type="button"
                    class="hc-action-btn hc-action-mute"
                    title="Mute"
                    onclick={(e) => { e.preventDefault(); e.stopPropagation(); handleMute(); }}
                  >
                    <span class="material-symbols-outlined">volume_off</span>
                  </button>
                  <button
                    type="button"
                    class="hc-action-btn hc-action-block"
                    title="Block"
                    onclick={(e) => { e.preventDefault(); e.stopPropagation(); handleBlock(); }}
                  >
                    <span class="material-symbols-outlined">block</span>
                  </button>
                </div>
              {/if}
            </div>
            <div class="hc-handle">@{account.acct || account.handle}</div>

            <div class="hc-stats">
              <span><strong>{account.followers_count ?? 0}</strong> Followers</span>
              <span><strong>{account.following_count ?? 0}</strong> Following</span>
            </div>

            {#if account.bio}
              <div class="hc-bio">{@html account.bio}</div>
            {/if}
          </div>
        </a>
      {/if}
    </div>
  {/if}
</span>

<style>
  .hover-card-trigger {
    position: relative;
    display: inline;
  }

  .hover-card {
    position: absolute;
    bottom: 100%;
    inset-inline-start: 0;
    margin-bottom: 8px;
    width: 320px;
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
    background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-primary-soft, rgba(0,128,128,0.3)) 100%);
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
    background: #f59e0b;
    color: white;
    border-color: #f59e0b;
  }

  .hc-action-block:hover {
    background: #dc2626;
    color: white;
    border-color: #dc2626;
  }

  .hc-action-btn:active {
    transform: scale(0.9);
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

<script lang="ts">
  import { api } from '$lib/api/client.js';
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
  let hoverTimer: ReturnType<typeof setTimeout> | null = null;
  let hideTimer: ReturnType<typeof setTimeout> | null = null;
  let cardEl: HTMLDivElement | undefined = $state();

  async function fetchAccount() {
    if (account || loading) return;
    loading = true;
    try {
      account = await api.get<Identity>(`/api/v1/accounts/lookup`, { acct: handle });
    } catch { /* */ }
    finally { loading = false; }
  }

  function show() {
    if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
    hoverTimer = setTimeout(() => {
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
</script>

<span
  class="hover-card-trigger"
  onmouseenter={show}
  onmouseleave={hide}
  onfocusin={show}
  onfocusout={hide}
>
  {@render children()}

  {#if visible}
    <div
      class="hover-card"
      bind:this={cardEl}
      onmouseenter={cancelHide}
      onmouseleave={hide}
    >
      {#if loading || !account}
        <div class="hc-loading">
          <div class="hc-skeleton-avatar"></div>
          <div class="hc-skeleton-line"></div>
          <div class="hc-skeleton-line short"></div>
        </div>
      {:else}
        <a href="/@{account.handle}" class="hc-link">
          {#if account.header_url}
            <div class="hc-header" style="background-image: url({account.header_url})"></div>
          {:else}
            <div class="hc-header hc-header-default"></div>
          {/if}

          <div class="hc-body">
            <div class="hc-avatar-row">
              {#if account.avatar_url}
                <img src={account.avatar_url} alt="" class="hc-avatar" />
              {:else}
                <div class="hc-avatar hc-avatar-placeholder">
                  {(account.display_name || account.handle).charAt(0).toUpperCase()}
                </div>
              {/if}
            </div>

            <div class="hc-name">{account.display_name || account.handle}</div>
            <div class="hc-handle">@{account.acct || account.handle}</div>

            {#if account.bio}
              <div class="hc-bio">{@html account.bio}</div>
            {/if}

            <div class="hc-stats">
              <span><strong>{account.following_count ?? 0}</strong> Following</span>
              <span><strong>{account.followers_count ?? 0}</strong> Followers</span>
            </div>
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
    width: 300px;
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 16px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
    z-index: 9000;
    overflow: hidden;
    animation: hc-in 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes hc-in {
    from { opacity: 0; transform: translateY(4px) scale(0.97); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }

  .hc-link {
    text-decoration: none;
    color: inherit;
    display: block;
  }

  .hc-header {
    height: 80px;
    background-size: cover;
    background-position: center;
    background-color: var(--color-primary-soft);
  }

  .hc-header-default {
    background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-primary-soft) 100%);
  }

  .hc-body {
    padding: 0 16px 14px;
  }

  .hc-avatar-row {
    margin-top: -24px;
    margin-bottom: 8px;
  }

  .hc-avatar {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    object-fit: cover;
    border: 3px solid var(--color-surface-container-lowest);
  }

  .hc-avatar-placeholder {
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary);
    color: white;
    font-weight: 700;
    font-size: 1.125rem;
  }

  .hc-name {
    font-size: 0.9375rem;
    font-weight: 700;
    color: var(--color-text);
  }

  .hc-handle {
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
    margin-bottom: 6px;
  }

  .hc-bio {
    font-size: 0.8125rem;
    color: var(--color-text);
    line-height: 1.4;
    margin-bottom: 8px;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .hc-bio :global(p) { margin: 0; }

  .hc-stats {
    display: flex;
    gap: 16px;
    font-size: 0.75rem;
    color: var(--color-text-secondary);
  }

  .hc-stats strong {
    color: var(--color-text);
    font-weight: 700;
  }

  /* Loading skeleton */
  .hc-loading {
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .hc-skeleton-avatar {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: var(--color-surface);
    animation: hc-pulse 1.2s ease-in-out infinite;
  }

  .hc-skeleton-line {
    height: 12px;
    width: 70%;
    border-radius: 6px;
    background: var(--color-surface);
    animation: hc-pulse 1.2s ease-in-out infinite;
  }

  .hc-skeleton-line.short { width: 40%; }

  @keyframes hc-pulse {
    0%, 100% { opacity: 0.4; }
    50% { opacity: 0.8; }
  }
</style>

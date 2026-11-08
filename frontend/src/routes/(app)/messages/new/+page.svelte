<script lang="ts">
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';
  import { goto } from '$app/navigation';
  import type { Identity } from '$lib/api/types.js';
  import { search } from '$lib/api/search.js';
  import { createConversation } from '$lib/api/conversations.js';
  import { getFollowing, getFollowers } from '$lib/api/accounts.js';
  import { currentUser } from '$lib/stores/auth.js';
  import { get } from 'svelte/store';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import { instanceName } from '$lib/stores/instance.js';

  let query = $state('');
  let results = $state<Identity[]>([]);
  let searching = $state(false);
  let creating = $state(false);
  let searchTimeout: ReturnType<typeof setTimeout> | undefined;
  let searchInputEl = $state<HTMLInputElement | undefined>();

  // Default suggestions shown before the user types: people they follow and
  // people who follow them (mutuals first). Gives a one-tap way to start a
  // chat with someone you actually know.
  let suggestions = $state<Identity[]>([]);
  let loadingSuggestions = $state(false);

  function asList(res: unknown): Identity[] {
    if (Array.isArray(res)) return res as Identity[];
    const data = (res as { data?: Identity[] })?.data;
    return Array.isArray(data) ? data : [];
  }

  async function loadSuggestions() {
    const me = get(currentUser);
    if (!me?.id) return;
    loadingSuggestions = true;
    try {
      const [followingRes, followersRes] = await Promise.all([
        getFollowing(me.id).catch(() => []),
        getFollowers(me.id).catch(() => []),
      ]);
      const following = asList(followingRes);
      const followers = asList(followersRes);
      const followerIds = new Set(followers.map((a) => a.id));
      const followingIds = new Set(following.map((a) => a.id));
      // Mutuals first, then the rest of following, then remaining followers.
      const ordered = [
        ...following.filter((a) => followerIds.has(a.id)),
        ...following.filter((a) => !followerIds.has(a.id)),
        ...followers.filter((a) => !followingIds.has(a.id)),
      ];
      const seen = new Set<string>();
      suggestions = ordered
        .filter((a) => a.id !== me.id && !seen.has(a.id) && (seen.add(a.id), true))
        .slice(0, 30);
    } catch {
      suggestions = [];
    } finally {
      loadingSuggestions = false;
    }
  }

  // Accept `?to=<handle>` (from "Chat with @user" on post cards or
  // the "Message" button on profiles). Search for the handle; if
  // there's one unambiguous result, start a conversation; otherwise
  // populate the search box and show the candidates so the user can
  // disambiguate. Remote handles are `alice@domain`; locals are bare.
  onMount(() => {
    if (!browser) return;
    const to = new URL(window.location.href).searchParams.get('to');
    if (to) {
      query = to.replace(/^@/, '');
      handleInput();
      resolveToHandle(query);
      return;
    }
    // No prefilled recipient — put the cursor in the search field and show
    // people the user follows / who follow them as quick starting points.
    searchInputEl?.focus();
    loadSuggestions();
  });

  async function resolveToHandle(handle: string) {
    searching = true;
    try {
      const res = await search(handle, { type: 'accounts', limit: 5 });
      const exact = res.accounts.find((a) => {
        const acct = (a as unknown as { acct?: string }).acct || a.handle;
        return (
          acct.toLowerCase() === handle.toLowerCase() ||
          a.handle.toLowerCase() === handle.toLowerCase()
        );
      });

      results = res.accounts;

      // Auto-start only on an exact match — otherwise the user could
      // land in a conversation with a similarly-named stranger.
      if (exact) startConversation(exact.id);
    } catch {
      results = [];
    } finally {
      searching = false;
    }
  }

  function handleInput() {
    if (searchTimeout) clearTimeout(searchTimeout);
    const q = query.trim();
    if (q.length < 2) {
      results = [];
      return;
    }
    searching = true;
    searchTimeout = setTimeout(async () => {
      try {
        const res = await search(q, { type: 'accounts', limit: 10 });
        results = res.accounts;
      } catch {
        results = [];
      } finally {
        searching = false;
      }
    }, 300);
  }

  async function startConversation(accountId: string) {
    if (creating) return;
    creating = true;
    try {
      const conv = await createConversation([accountId]);
      goto(`/messages/${conv.id}`);
    } catch (e: unknown) {
      creating = false;

      // Peer software doesn't speak a real DM primitive. Instead of
      // erroring, silently pivot to composing a direct-visibility
      // post addressed to the same recipient — that's how Mastodon
      // users actually receive "DMs" today.
      const err = e as {
        body?: {
          error?: string;
          fallback?: string;
          recipient?: {
            handle?: string;
            display_name?: string | null;
            ap_actor_url?: string;
          };
        };
      };

      if (
        err?.body?.error === 'dm.not_supported_by_peer' &&
        err?.body?.fallback === 'direct_post' &&
        err.body.recipient
      ) {
        const r = err.body.recipient;
        const mention = remoteMentionHandle(r.handle, r.ap_actor_url);
        // Leave /messages/new first so the composer (hidden on DM
        // routes) renders, then dispatch the open event. A frame of
        // delay is enough for the route transition to mount the FAB
        // layout.
        goto('/home');
        setTimeout(() => {
          window.dispatchEvent(
            new CustomEvent('open-composer', {
              detail: {
                prefill: `${mention} `,
                visibility: 'direct',
              },
            }),
          );
        }, 50);
      }
    }
  }

  // Convert a bare handle + actor URL into a federation-safe mention
  // token. We DON'T use the `handle` field from the backend —
  // that's our locally-munged collision-safe string
  // (e.g. `tester_mastodon_dd1e97`), which the remote server won't
  // recognize. Instead we pull the real handle from the AP actor
  // URL's last path segment — Mastodon, Pleroma, Misskey all use
  // `/users/{handle}` or `/@{handle}` shapes.
  function remoteMentionHandle(handle?: string, apActorUrl?: string): string {
    if (!apActorUrl) return handle ? `@${handle}` : '';

    try {
      const u = new URL(apActorUrl);
      const segments = u.pathname.split('/').filter(Boolean);
      const remoteHandle = segments[segments.length - 1] || handle || '';
      // Strip leading `@` when Mastodon-style `/@handle` paths are used.
      const clean = remoteHandle.startsWith('@') ? remoteHandle.slice(1) : remoteHandle;
      return clean ? `@${clean}@${u.host}` : '';
    } catch {
      return handle ? `@${handle}` : '';
    }
  }

  function goBack() {
    goto('/messages');
  }
</script>

<svelte:head>
  <title>New Message - {$instanceName}</title>
</svelte:head>

<div class="new-message-page">
  <div class="page-header">
    <button type="button" class="back-btn" onclick={goBack} aria-label="Back to messages">
      <svg class="rtl-mirror" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="15 18 9 12 15 6" />
      </svg>
    </button>
    <h1 class="page-title">New Message</h1>
  </div>

  <div class="search-section">
    <label for="user-search" class="search-label">To:</label>
    <input
      id="user-search"
      type="text"
      class="input search-input"
      placeholder="Search for a user..."
      bind:this={searchInputEl}
      bind:value={query}
      oninput={handleInput}
      autocomplete="off"
    />
  </div>

  {#snippet personButton(account: Identity)}
    <li>
      <button
        type="button"
        class="result-item"
        onclick={() => startConversation(account.id)}
        disabled={creating}
      >
        <Avatar src={account.avatar_url} name={account.display_name || account.handle} size="md" />
        <div class="result-info">
          <span class="result-name">{account.display_name || account.handle}</span>
          <span class="result-handle">@{account.handle}</span>
        </div>
      </button>
    </li>
  {/snippet}

  <div class="results-section">
    {#if searching}
      <div class="results-loading">
        <Spinner size={20} />
      </div>
    {:else if results.length > 0}
      <ul class="results-list" role="listbox" aria-label="Search results">
        {#each results as account (account.id)}{@render personButton(account)}{/each}
      </ul>
    {:else if query.trim().length >= 2}
      <div class="results-empty">
        <p class="empty-text">No users found</p>
      </div>
    {:else if loadingSuggestions}
      <div class="results-loading">
        <Spinner size={20} />
      </div>
    {:else if suggestions.length > 0}
      <p class="suggestions-label">Suggested</p>
      <ul class="results-list" role="listbox" aria-label="Suggested people">
        {#each suggestions as account (account.id)}{@render personButton(account)}{/each}
      </ul>
    {:else}
      <div class="results-empty">
        <p class="empty-text">Search for someone to message</p>
      </div>
    {/if}
  </div>

  {#if creating}
    <div class="creating-overlay">
      <Spinner />
      <p>Starting conversation...</p>
    </div>
  {/if}
</div>

<style>
  .new-message-page {
    display: flex;
    flex-direction: column;
    max-width: var(--feed-max-width);
    margin: 0 auto;
    width: 100%;
  }

  .page-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding-block-end: var(--space-4);
    border-block-end: 1px solid var(--color-border);
    margin-block-end: var(--space-4);
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

  .page-title {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
  }

  .search-section {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding-block-end: var(--space-4);
  }

  .search-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
    flex-shrink: 0;
  }

  .search-input {
    flex: 1;
  }

  .results-section {
    flex: 1;
  }

  .results-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-8);
  }

  .results-list {
    display: flex;
    flex-direction: column;
  }

  .suggestions-label {
    margin: 0 0 var(--space-1);
    padding-inline: var(--space-2);
    font-size: var(--text-xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-tertiary);
  }

  .result-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border: none;
    background: none;
    width: 100%;
    text-align: start;
    cursor: pointer;
    border-radius: var(--radius-lg);
    transition: background var(--transition-fast);
  }

  .result-item:hover:not(:disabled) {
    background: var(--color-surface);
  }

  .result-item:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .result-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .result-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .result-handle {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .results-empty {
    display: flex;
    justify-content: center;
    padding: var(--space-8);
  }

  .empty-text {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .creating-overlay {
    position: fixed;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-3);
    background: var(--color-overlay);
    z-index: var(--z-modal);
    color: white;
    font-size: var(--text-sm);
  }
</style>

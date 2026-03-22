<script lang="ts">
  import { goto } from '$app/navigation';
  import type { Identity } from '$lib/api/types.js';
  import { search } from '$lib/api/search.js';
  import { createConversation } from '$lib/api/conversations.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let query = $state('');
  let results = $state<Identity[]>([]);
  let searching = $state(false);
  let creating = $state(false);
  let searchTimeout: ReturnType<typeof setTimeout> | undefined;

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
    } catch {
      creating = false;
    }
  }

  function goBack() {
    goto('/messages');
  }
</script>

<svelte:head>
  <title>New Message - HybridSocial</title>
</svelte:head>

<div class="new-message-page">
  <div class="page-header">
    <button type="button" class="back-btn" onclick={goBack} aria-label="Back to messages">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
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
      bind:value={query}
      oninput={handleInput}
      autocomplete="off"
    />
  </div>

  <div class="results-section">
    {#if searching}
      <div class="results-loading">
        <Spinner size={20} />
      </div>
    {:else if results.length > 0}
      <ul class="results-list" role="listbox" aria-label="Search results">
        {#each results as account (account.id)}
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
        {/each}
      </ul>
    {:else if query.trim().length >= 2}
      <div class="results-empty">
        <p class="empty-text">No users found</p>
      </div>
    {:else}
      <div class="results-empty">
        <p class="empty-text">Type at least 2 characters to search</p>
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

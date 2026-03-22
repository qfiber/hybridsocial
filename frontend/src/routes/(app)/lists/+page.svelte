<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import type { List } from '$lib/api/lists.js';
  import { getLists, createList } from '$lib/api/lists.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';

  let lists = $state<List[]>([]);
  let loading = $state(true);
  let showCreateModal = $state(false);
  let newListTitle = $state('');
  let creating = $state(false);

  onMount(async () => {
    try {
      lists = await getLists();
    } catch {
      // Error loading lists
    } finally {
      loading = false;
    }
  });

  async function handleCreate() {
    const title = newListTitle.trim();
    if (!title || creating) return;
    creating = true;
    try {
      const list = await createList(title);
      lists = [list, ...lists];
      showCreateModal = false;
      newListTitle = '';
    } catch {
      // Error creating
    } finally {
      creating = false;
    }
  }

  function openList(id: string) {
    goto(`/lists/${id}`);
  }
</script>

<svelte:head>
  <title>Lists - HybridSocial</title>
</svelte:head>

<div class="lists-page">
  <div class="page-header">
    <h1 class="page-title">Lists</h1>
    <button type="button" class="btn btn-primary btn-sm" onclick={() => (showCreateModal = true)}>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <line x1="12" y1="5" x2="12" y2="19" />
        <line x1="5" y1="12" x2="19" y2="12" />
      </svg>
      New List
    </button>
  </div>

  {#if loading}
    <div class="page-loading">
      <Spinner />
    </div>
  {:else if lists.length === 0}
    <div class="page-empty">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--color-text-tertiary)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M4 6h16M4 10h16M4 14h16M4 18h16" />
      </svg>
      <p class="empty-title">No lists yet</p>
      <p class="empty-hint">Lists help you organize the accounts you follow into curated timelines.</p>
      <button type="button" class="btn btn-primary" onclick={() => (showCreateModal = true)}>
        Create your first list
      </button>
    </div>
  {:else}
    <ul class="list-items">
      {#each lists as list (list.id)}
        <li>
          <button type="button" class="list-item" onclick={() => openList(list.id)}>
            <div class="list-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M4 6h16M4 10h16M4 14h16M4 18h16" />
              </svg>
            </div>
            <div class="list-info">
              <span class="list-name">{list.name || list.title || 'Untitled'}</span>
              <span class="list-count">
                {(list.member_count ?? 0) === 1 ? '1 member' : `${list.member_count ?? 0} members`}
              </span>
            </div>
            <svg class="list-chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="9 18 15 12 9 6" />
            </svg>
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</div>

<Modal bind:open={showCreateModal} title="New List" onclose={() => { newListTitle = ''; }}>
  <form class="create-form" onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
    <div class="form-group">
      <label for="list-title" class="form-label">List Name</label>
      <input
        id="list-title"
        type="text"
        class="input"
        placeholder="e.g., Tech News"
        bind:value={newListTitle}
        required
      />
    </div>
    <div class="form-actions">
      <button type="button" class="btn btn-ghost" onclick={() => (showCreateModal = false)}>Cancel</button>
      <button type="submit" class="btn btn-primary" disabled={!newListTitle.trim() || creating}>
        {creating ? 'Creating...' : 'Create List'}
      </button>
    </div>
  </form>
</Modal>

<style>
  .lists-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    width: 100%;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-block-end: var(--space-4);
    border-block-end: 1px solid var(--color-border);
    margin-block-end: var(--space-4);
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .page-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-16);
  }

  .page-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-4);
    padding: var(--space-16) var(--space-4);
    text-align: center;
  }

  .empty-title {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
  }

  .empty-hint {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    max-width: 320px;
    line-height: 1.5;
  }

  .list-items {
    display: flex;
    flex-direction: column;
  }

  .list-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-4);
    border: none;
    background: none;
    width: 100%;
    text-align: start;
    cursor: pointer;
    border-block-end: 1px solid var(--color-border);
    transition: background var(--transition-fast);
  }

  .list-item:last-child {
    border-block-end: none;
  }

  .list-item:hover {
    background: var(--color-surface);
  }

  .list-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border-radius: var(--radius-lg);
    background: var(--color-primary-soft);
    color: var(--color-primary);
    flex-shrink: 0;
  }

  .list-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .list-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .list-count {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .list-chevron {
    color: var(--color-text-tertiary);
    flex-shrink: 0;
  }

  .create-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .form-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
  }
</style>

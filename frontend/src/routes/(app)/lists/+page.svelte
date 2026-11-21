<script lang="ts">
  import { onMount } from 'svelte';
  import type { List } from '$lib/api/lists.js';
  import { getLists, createList, updateList, deleteList } from '$lib/api/lists.js';
  import { addToast } from '$lib/stores/toast.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import Dropdown from '$lib/components/ui/Dropdown.svelte';
  import { instanceName } from '$lib/stores/instance.js';

  let lists = $state<List[]>([]);
  let loading = $state(true);
  let loadError = $state(false);

  // A single modal serves both create and rename: editingList === null
  // means "create", otherwise we're renaming that list.
  let showFormModal = $state(false);
  let editingList = $state<List | null>(null);
  let formTitle = $state('');
  let saving = $state(false);

  async function load() {
    loading = true;
    loadError = false;
    try {
      lists = await getLists();
    } catch {
      loadError = true;
    } finally {
      loading = false;
    }
  }

  onMount(load);

  function listName(list: List): string {
    return list.name || list.title || 'Untitled';
  }

  function openCreate() {
    editingList = null;
    formTitle = '';
    showFormModal = true;
  }

  function openRename(list: List) {
    editingList = list;
    formTitle = listName(list);
    showFormModal = true;
  }

  async function handleSubmit() {
    const title = formTitle.trim();
    if (!title || saving) return;
    saving = true;
    const target = editingList;
    try {
      if (target) {
        const updated = await updateList(target.id, title);
        lists = lists.map((l) => (l.id === target.id ? { ...l, ...updated } : l));
        addToast('List renamed', 'success');
      } else {
        const list = await createList(title);
        lists = [list, ...lists];
        addToast('List created', 'success');
      }
      showFormModal = false;
      formTitle = '';
      editingList = null;
    } catch {
      addToast(target ? 'Could not rename list' : 'Could not create list', 'error');
    } finally {
      saving = false;
    }
  }

  async function handleDelete(list: List) {
    if (!confirm(`Delete "${listName(list)}"? This cannot be undone.`)) return;
    const prev = lists;
    // Optimistic removal; restore on failure.
    lists = lists.filter((l) => l.id !== list.id);
    try {
      await deleteList(list.id);
      addToast('List deleted', 'success');
    } catch {
      lists = prev;
      addToast('Could not delete list', 'error');
    }
  }

  function memberLabel(n: number): string {
    return n === 1 ? '1 member' : `${n} members`;
  }

  // Focus the name field when the modal opens. Runs after the Modal's
  // own initial-focus rAF (which would otherwise land on the × button).
  function focusOnOpen(node: HTMLInputElement) {
    requestAnimationFrame(() => requestAnimationFrame(() => node.focus()));
  }
</script>

<svelte:head>
  <title>Lists - {$instanceName}</title>
</svelte:head>

<div class="lists-page">
  <div class="sticky-section-head page-header">
    <h1 class="page-title">Lists</h1>
    <button type="button" class="btn btn-primary btn-sm" onclick={openCreate}>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <line x1="12" y1="5" x2="12" y2="19" />
        <line x1="5" y1="12" x2="19" y2="12" />
      </svg>
      New List
    </button>
  </div>

  {#if loading}
    <ul class="list-items" aria-hidden="true">
      {#each Array(5) as _, i (i)}
        <li class="skel-item">
          <span class="skel-icon"></span>
          <span class="skel-lines">
            <span class="skel-line skel-line-lg"></span>
            <span class="skel-line skel-line-sm"></span>
          </span>
        </li>
      {/each}
    </ul>
  {:else if loadError}
    <div class="page-empty">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--color-text-tertiary)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="10" /><line x1="12" y1="8" x2="12" y2="12" /><line x1="12" y1="16" x2="12.01" y2="16" />
      </svg>
      <p class="empty-title">Couldn't load your lists</p>
      <p class="empty-hint">Something went wrong reaching the server. Check your connection and try again.</p>
      <button type="button" class="btn btn-primary" onclick={load}>Retry</button>
    </div>
  {:else if lists.length === 0}
    <div class="page-empty">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--color-text-tertiary)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M4 6h16M4 10h16M4 14h16M4 18h16" />
      </svg>
      <p class="empty-title">No lists yet</p>
      <p class="empty-hint">Lists group accounts you follow into their own focused, chronological timeline, like Friends or News. Create one, add people to it, then open it to read only their posts, away from your Home feed.</p>
      <button type="button" class="btn btn-primary" onclick={openCreate}>
        Create your first list
      </button>
    </div>
  {:else}
    <div class="lists-intro">
      <svg class="lists-intro-icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <circle cx="12" cy="12" r="10" /><line x1="12" y1="16" x2="12" y2="12" /><line x1="12" y1="8" x2="12.01" y2="8" />
      </svg>
      <p>
        Lists group accounts you follow into their own focused, chronological
        timeline, like <strong>Friends</strong> or <strong>News</strong>. Open a
        list to read only its members' posts, away from your Home feed. Use
        <strong>New List</strong> to create one, and each list's <strong>⋯</strong>
        menu to rename or delete it. Open a list to manage who's in it.
      </p>
    </div>
    <ul class="list-items">
      {#each lists as list (list.id)}
        <li class="list-item">
          <a class="list-link" href="/lists/{list.id}">
            <div class="list-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M4 6h16M4 10h16M4 14h16M4 18h16" />
              </svg>
            </div>
            <div class="list-info">
              <span class="list-name">{listName(list)}</span>
              <span class="list-count">{memberLabel(list.member_count ?? 0)}</span>
            </div>
          </a>
          <div class="list-actions">
            <Dropdown align="end">
              {#snippet trigger()}
                <span class="list-menu-btn">
                  <span class="sr-only">Actions for {listName(list)}</span>
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                    <circle cx="12" cy="5" r="1" /><circle cx="12" cy="12" r="1" /><circle cx="12" cy="19" r="1" />
                  </svg>
                </span>
              {/snippet}
              <button type="button" onclick={() => openRename(list)}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                  <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7" />
                  <path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z" />
                </svg>
                Rename
              </button>
              <button type="button" class="menu-danger" onclick={() => handleDelete(list)}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                  <polyline points="3 6 5 6 21 6" />
                  <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2" />
                </svg>
                Delete
              </button>
            </Dropdown>
          </div>
        </li>
      {/each}
    </ul>
  {/if}
</div>

<Modal
  bind:open={showFormModal}
  title={editingList ? 'Rename List' : 'New List'}
  onclose={() => { formTitle = ''; editingList = null; }}
>
  <form class="create-form" onsubmit={(e) => { e.preventDefault(); handleSubmit(); }}>
    <div class="form-group">
      <label for="list-title" class="form-label">List Name</label>
      <input
        id="list-title"
        type="text"
        class="input"
        placeholder="e.g., Tech News"
        bind:value={formTitle}
        use:focusOnOpen
        required
      />
    </div>
    <div class="form-actions">
      <button type="button" class="btn btn-ghost" onclick={() => (showFormModal = false)}>Cancel</button>
      <button type="submit" class="btn btn-primary" disabled={!formTitle.trim() || saving}>
        {saving ? (editingList ? 'Saving…' : 'Creating…') : (editingList ? 'Save' : 'Create List')}
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

  .lists-intro {
    display: flex;
    align-items: flex-start;
    gap: var(--space-2);
    padding: var(--space-3);
    margin-block-end: var(--space-3);
    background: var(--color-surface-container);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    line-height: 1.5;
  }

  .lists-intro p {
    margin: 0;
  }

  .lists-intro-icon {
    flex-shrink: 0;
    margin-block-start: 2px;
    color: var(--color-primary);
  }

  .lists-intro strong {
    color: var(--color-text);
    font-weight: 600;
  }

  .list-items {
    display: flex;
    flex-direction: column;
  }

  .list-item {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    border-block-end: 1px solid var(--color-border);
    transition: background var(--transition-fast);
  }

  .list-item:last-child {
    border-block-end: none;
  }

  .list-item:hover,
  .list-item:focus-within {
    background: var(--color-surface);
  }

  /* The navigable area is a real link now (open-in-new-tab, middle
     click); the ⋯ menu lives outside it as a sibling. */
  .list-link {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-4);
    text-decoration: none;
    color: inherit;
    border-radius: var(--radius-md);
  }

  .list-link:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: -2px;
    text-decoration: none;
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
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .list-count {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  /* ---- Row action menu (⋯) ---- */
  .list-actions {
    flex-shrink: 0;
    padding-inline-end: var(--space-3);
  }

  .list-menu-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    color: var(--color-text-tertiary);
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .list-menu-btn:hover {
    background: var(--color-surface-container-low);
    color: var(--color-text);
  }

  .list-actions :global(.dropdown-trigger:focus-visible) {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
    border-radius: var(--radius-full);
  }

  .menu-danger {
    color: var(--color-destructive, #dc2626);
  }

  /* ---- Skeleton loading rows ---- */
  .skel-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-4);
    border-block-end: 1px solid var(--color-border);
  }

  .skel-item:last-child {
    border-block-end: none;
  }

  .skel-icon {
    width: 40px;
    height: 40px;
    border-radius: var(--radius-lg);
    background: var(--color-border);
    flex-shrink: 0;
  }

  .skel-lines {
    display: flex;
    flex-direction: column;
    gap: 8px;
    flex: 1;
    min-width: 0;
  }

  .skel-line {
    height: 10px;
    border-radius: var(--radius-sm);
    background: var(--color-border);
  }

  .skel-line-lg { width: 45%; }
  .skel-line-sm { width: 25%; }

  @media (prefers-reduced-motion: no-preference) {
    .skel-icon,
    .skel-line {
      animation: skeleton-pulse 1.5s ease-in-out infinite;
    }
  }

  @keyframes skeleton-pulse {
    0%, 100% { opacity: 0.4; }
    50% { opacity: 0.7; }
  }

  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
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

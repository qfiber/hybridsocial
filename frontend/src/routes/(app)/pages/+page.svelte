<script lang="ts">
  import { onMount } from 'svelte';
  import { getPages, createPage } from '$lib/api/pages.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let pages: any[] = $state([]);
  let loading = $state(true);
  let error = $state('');

  // Create modal
  let showCreateModal = $state(false);
  let createData = $state({
    handle: '',
    display_name: '',
    description: '',
    website: '',
    category: '',
  });
  let creating = $state(false);
  let createError = $state('');

  const categories = [
    'Business',
    'Technology',
    'Arts & Culture',
    'Education',
    'Non-Profit',
    'Media',
    'Government',
    'Health',
    'Sports',
    'Other',
  ];

  async function loadPages() {
    loading = true;
    error = '';
    try {
      const result = await getPages();
      pages = Array.isArray(result) ? result : [];
    } catch {
      error = 'Failed to load pages.';
    } finally {
      loading = false;
    }
  }

  function openCreateModal() {
    createData = { handle: '', display_name: '', description: '', website: '', category: '' };
    createError = '';
    showCreateModal = true;
  }

  async function handleCreate() {
    if (!createData.handle.trim() || !createData.display_name.trim()) {
      createError = 'Handle and display name are required.';
      return;
    }
    creating = true;
    createError = '';
    try {
      const newPage = await createPage(createData);
      pages = [newPage, ...pages];
      showCreateModal = false;
    } catch {
      createError = 'Failed to create page. Please try again.';
    } finally {
      creating = false;
    }
  }

  onMount(() => {
    loadPages();
  });
</script>

<svelte:head>
  <title>Pages - HybridSocial</title>
</svelte:head>

<div class="pages-page">
  <div class="page-header">
    <h1 class="page-title">Pages</h1>
    <button type="button" class="btn btn-primary" onclick={openCreateModal}>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
      </svg>
      Create Page
    </button>
  </div>

  {#if loading}
    <div class="loading-state">
      <Spinner />
    </div>
  {:else if error}
    <div class="error-state">
      <p>{error}</p>
      <button type="button" class="btn btn-outline" onclick={loadPages}>Retry</button>
    </div>
  {:else if pages.length === 0}
    <div class="empty-state">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--color-text-tertiary)" stroke-width="1.5" aria-hidden="true">
        <path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>
        <polyline points="9 22 9 12 15 12 15 22"/>
      </svg>
      <p class="empty-text">No pages yet</p>
      <p class="empty-sub">Create a page for your business or organization.</p>
    </div>
  {:else}
    <div class="pages-grid">
      {#each pages as pg (pg.id)}
        <a href="/pages/{pg.id}" class="page-card">
          <div class="page-card-avatar">
            <Avatar src={pg.avatar_url || pg.logo_url} name={pg.display_name || pg.name || pg.handle} size="lg" />
          </div>
          <div class="page-card-info">
            <h3 class="page-card-name">{pg.display_name || pg.name || pg.handle}</h3>
            {#if pg.category}
              <span class="page-card-category">{pg.category}</span>
            {/if}
            {#if pg.followers_count !== undefined}
              <span class="page-card-followers">{pg.followers_count} followers</span>
            {/if}
          </div>
        </a>
      {/each}
    </div>
  {/if}
</div>

<Modal bind:open={showCreateModal} title="Create Page">
  <div class="create-form">
    <div class="form-group">
      <label class="form-label" for="page-handle">Handle</label>
      <input id="page-handle" type="text" class="form-input" bind:value={createData.handle} placeholder="my-page" />
    </div>
    <div class="form-group">
      <label class="form-label" for="page-name">Display Name</label>
      <input id="page-name" type="text" class="form-input" bind:value={createData.display_name} placeholder="My Page" />
    </div>
    <div class="form-group">
      <label class="form-label" for="page-desc">Description</label>
      <textarea id="page-desc" class="form-textarea" bind:value={createData.description} placeholder="What is this page about?" rows="3"></textarea>
    </div>
    <div class="form-group">
      <label class="form-label" for="page-website">Website</label>
      <input id="page-website" type="url" class="form-input" bind:value={createData.website} placeholder="https://example.com" />
    </div>
    <div class="form-group">
      <label class="form-label" for="page-category">Category</label>
      <select id="page-category" class="form-select" bind:value={createData.category}>
        <option value="">Select a category</option>
        {#each categories as cat (cat)}
          <option value={cat}>{cat}</option>
        {/each}
      </select>
    </div>

    {#if createError}
      <p class="form-error">{createError}</p>
    {/if}

    <div class="form-actions">
      <button type="button" class="btn btn-ghost" onclick={() => (showCreateModal = false)}>Cancel</button>
      <button type="button" class="btn btn-primary" onclick={handleCreate} disabled={creating}>
        {creating ? 'Creating...' : 'Create Page'}
      </button>
    </div>
  </div>
</Modal>

<style>
  .pages-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-4);
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .loading-state {
    display: flex;
    justify-content: center;
    padding: var(--space-16);
  }

  .error-state,
  .empty-state {
    text-align: center;
    padding: var(--space-16) var(--space-4);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-3);
  }

  .empty-text {
    font-size: var(--text-base);
    color: var(--color-text-tertiary);
  }

  .empty-sub {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .pages-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: var(--space-3);
  }

  .page-card {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-4);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    text-decoration: none;
    color: var(--color-text);
    transition: box-shadow var(--transition-fast), transform var(--transition-fast);
  }

  .page-card:hover {
    box-shadow: var(--shadow-md);
    transform: translateY(-1px);
    text-decoration: none;
  }

  .page-card-info {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    min-width: 0;
  }

  .page-card-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .page-card-category {
    font-size: var(--text-xs);
    color: var(--color-primary);
    background: var(--color-primary-soft);
    padding: 1px var(--space-2);
    border-radius: var(--radius-sm);
    align-self: flex-start;
  }

  .page-card-followers {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  /* Buttons */
  .btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-2) var(--space-3);
    border: none;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .btn-primary {
    background: var(--color-primary);
    color: var(--color-text-inverse);
  }

  .btn-primary:hover {
    background: var(--color-primary-hover);
  }

  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .btn-ghost {
    background: transparent;
    color: var(--color-text-secondary);
  }

  .btn-ghost:hover {
    background: var(--color-surface);
  }

  .btn-outline {
    background: transparent;
    border: 1px solid var(--color-border);
    color: var(--color-text);
  }

  /* Create form */
  .create-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .form-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .form-input,
  .form-textarea,
  .form-select {
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-bg);
    font-family: inherit;
  }

  .form-input:focus,
  .form-textarea:focus,
  .form-select:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .form-textarea {
    resize: vertical;
  }

  .form-error {
    font-size: var(--text-sm);
    color: var(--color-danger);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
  }
</style>

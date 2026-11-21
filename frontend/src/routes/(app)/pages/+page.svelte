<script lang="ts">
  import { onMount } from 'svelte';
  import { getPages, createPage } from '$lib/api/pages.js';
  import { api } from '$lib/api/client.js';
  import EntityCard from '$lib/components/entity/EntityCard.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import { instanceName } from '$lib/stores/instance.js';

  let pages: any[] = $state([]);
  let loading = $state(true);
  let error = $state('');
  let query = $state('');
  // Selected category for the filter dropdown. Empty string = "All".
  // Stored as a separate state so the search box and category filter
  // compose (search within a category, or browse a category without
  // typing anything).
  let categoryFilter = $state('');

  // Helper so category comparisons survive minor casing differences
  // between the form's preset list and any free-text categories that
  // got entered before the dropdown existed.
  function pageCategory(p: any): string {
    return (p?.organization?.category || p?.category || '').trim();
  }

  // The dropdown options are derived from the actual pages on screen
  // rather than the hard-coded create-form list — that way a page
  // with a custom / legacy category still shows up as filterable, and
  // an empty deployment doesn't list every theoretical option.
  let availableCategories = $derived.by(() => {
    const set = new Set<string>();
    for (const p of pages) {
      const c = pageCategory(p);
      if (c) set.add(c);
    }
    return [...set].sort((a, b) => a.localeCompare(b));
  });

  // Client-side filter — pages list is small enough that the round
  // trip to a server-side search isn't worth it. Match against the
  // human-readable fields a user would type to find a page, and
  // intersect with the category filter when one's selected.
  let visiblePages = $derived.by(() => {
    const q = query.trim().toLowerCase();
    const cat = categoryFilter.trim().toLowerCase();
    return pages.filter((p) => {
      if (cat && pageCategory(p).toLowerCase() !== cat) return false;
      if (!q) return true;
      const haystack = [
        p.display_name,
        p.name,
        p.handle,
        p.bio,
        p.organization?.category,
        p.category,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      return haystack.includes(q);
    });
  });

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

  // Live handle availability check. The /api/v1/accounts/lookup
  // endpoint returns 404 when no identity owns the handle, which is
  // the cheapest signal we can probe for "available". A short debounce
  // keeps us from hitting the lookup on every keystroke.
  let handleStatus = $state<'idle' | 'checking' | 'available' | 'taken' | 'invalid'>('idle');
  let handleCheckTimer: ReturnType<typeof setTimeout> | null = null;
  let handleCheckSeq = 0;
  $effect(() => {
    const raw = createData.handle.trim();
    if (handleCheckTimer) clearTimeout(handleCheckTimer);
    if (raw.length === 0) {
      handleStatus = 'idle';
      return;
    }
    if (!/^[a-zA-Z0-9_]{1,20}$/.test(raw)) {
      handleStatus = 'invalid';
      return;
    }
    handleStatus = 'checking';
    const seq = ++handleCheckSeq;
    handleCheckTimer = setTimeout(async () => {
      try {
        await api.get(`/api/v1/accounts/lookup`, { handle: raw });
        if (seq === handleCheckSeq) handleStatus = 'taken';
      } catch (e: any) {
        if (seq !== handleCheckSeq) return;
        if (e?.status === 404) {
          handleStatus = 'available';
        } else {
          handleStatus = 'idle';
        }
      }
    }, 350);
  });

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
    'Religious',
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
    } catch (e: any) {
      // Backend returns { error: "validation.failed", details: { handle: ["has already been taken"] } }
      // when the requested handle collides with another identity.
      const handleErrs: string[] | undefined = e?.body?.details?.handle;
      if (handleErrs?.some((m) => /taken|exist|use|unique/i.test(m))) {
        createError = `The handle "@${createData.handle.trim()}" is already in use. Please choose a different one.`;
      } else if (e?.body?.details?.handle?.length) {
        createError = `Handle: ${e.body.details.handle[0]}`;
      } else {
        createError = e?.body?.message || 'Failed to create page. Please try again.';
      }
    } finally {
      creating = false;
    }
  }

  onMount(() => {
    loadPages();
  });
</script>

<svelte:head>
  <title>Pages - {$instanceName}</title>
</svelte:head>

<div class="pages-page">
  <div class="sticky-section-head">
    <div class="page-header">
      <h1 class="page-title">Pages</h1>
      <button type="button" class="btn btn-primary" onclick={openCreateModal}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
        </svg>
        Create Page
      </button>
    </div>

    <div class="pages-toolbar">
      <div class="search-bar">
        <svg class="search-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <circle cx="11" cy="11" r="8" />
          <line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
        <input
          type="search"
          class="search-input"
          placeholder="Search pages…"
          bind:value={query}
          aria-label="Search pages"
        />
        {#if query}
          <button type="button" class="search-clear" onclick={() => (query = '')} aria-label="Clear search">
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2">
              <line x1="4" y1="4" x2="16" y2="16" />
              <line x1="16" y1="4" x2="4" y2="16" />
            </svg>
          </button>
        {/if}
      </div>

      {#if availableCategories.length > 0}
        <select
          class="category-filter"
          bind:value={categoryFilter}
          aria-label="Filter by category"
        >
          <option value="">All categories</option>
          {#each availableCategories as cat (cat)}
            <option value={cat}>{cat}</option>
          {/each}
        </select>
      {/if}
    </div>
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
  {:else if visiblePages.length === 0}
    <div class="empty-state">
      <p class="empty-text">No pages match "{query}"</p>
    </div>
  {:else}
    <div class="pages-grid">
      {#each visiblePages as pg (pg.id)}
        {@const name = pg.display_name || pg.name || pg.handle}
        {@const category = pg.organization?.category || pg.category}
        <EntityCard
          {name}
          handle={pg.handle}
          avatarUrl={pg.avatar_url || pg.logo_url}
          coverUrl={pg.header_url}
          description={pg.bio}
          badge={category}
          count={pg.followers_count ?? 0}
          countLabel="followers"
          href="/pages/{pg.id}"
        />
      {/each}
    </div>
  {/if}
</div>

<Modal bind:open={showCreateModal} title="Create Page">
  <div class="create-form">
    <div class="form-group">
      <label class="form-label" for="page-handle">Handle</label>
      <input
        id="page-handle"
        type="text"
        class="form-input"
        class:form-input-invalid={handleStatus === 'taken' || handleStatus === 'invalid'}
        bind:value={createData.handle}
        placeholder="my_page"
        autocomplete="off"
        aria-invalid={handleStatus === 'taken' || handleStatus === 'invalid'}
        aria-describedby="page-handle-status"
      />
      <p
        id="page-handle-status"
        class="handle-status handle-status-{handleStatus}"
        aria-live="polite"
      >
        {#if handleStatus === 'checking'}
          Checking availability…
        {:else if handleStatus === 'available'}
          ✓ "@{createData.handle.trim()}" is available
        {:else if handleStatus === 'taken'}
          ✕ "@{createData.handle.trim()}" is already in use — please choose a different one
        {:else if handleStatus === 'invalid'}
          Only letters, numbers, and underscores; up to 20 characters
        {:else}
          &nbsp;
        {/if}
      </p>
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
      <button type="button" class="btn btn-primary" onclick={handleCreate} disabled={creating || handleStatus === 'taken' || handleStatus === 'invalid' || handleStatus === 'checking'}>
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

  /* Search + filter row */
  .pages-toolbar {
    display: flex;
    align-items: stretch;
    gap: var(--space-2);
    margin-block-end: var(--space-4);
  }

  @media (max-width: 560px) {
    .pages-toolbar {
      flex-direction: column;
    }
  }

  .search-bar {
    position: relative;
    display: flex;
    align-items: center;
    flex: 1;
    min-width: 0;
  }

  .category-filter {
    flex-shrink: 0;
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    color: var(--color-text);
    font-size: var(--text-sm);
    cursor: pointer;
    min-width: 160px;
    transition: border-color var(--transition-fast);
  }

  .category-filter:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .search-icon {
    position: absolute;
    inset-inline-start: var(--space-3);
    color: var(--color-text-tertiary);
    pointer-events: none;
  }

  .search-input {
    width: 100%;
    padding: var(--space-3) var(--space-10);
    padding-inline-start: calc(var(--space-3) + 24px);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
  }

  .search-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft);
  }

  .search-clear {
    position: absolute;
    inset-inline-end: var(--space-3);
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    color: var(--color-text-tertiary);
    border-radius: var(--radius-full);
    cursor: pointer;
    padding: 0;
  }

  .search-clear:hover {
    color: var(--color-text);
    background: var(--color-surface);
  }

  /* 2 cards per row on desktop, 1 on narrower viewports. */
  .pages-grid {
    display: grid;
    grid-template-columns: 1fr;
    gap: var(--space-4);
  }

  @media (min-width: 720px) {
    .pages-grid {
      grid-template-columns: 1fr 1fr;
    }
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
    color: var(--color-on-primary);
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

  .form-input-invalid {
    border-color: var(--color-danger, #dc2626);
  }

  .handle-status {
    margin: 4px 0 0;
    font-size: 12px;
    min-height: 1.1em;
    color: var(--color-text-secondary);
  }

  .handle-status-checking {
    color: var(--color-text-secondary);
  }

  .handle-status-available {
    color: var(--color-success, #16a34a);
  }

  .handle-status-taken,
  .handle-status-invalid {
    color: var(--color-danger, #dc2626);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
  }
</style>

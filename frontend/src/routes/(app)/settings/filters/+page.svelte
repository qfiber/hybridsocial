<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import { reloadFilters } from '$lib/stores/content-filters.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface ContentFilter {
    id: string;
    phrase: string;
    context: string[];
    action: string;
    whole_word: boolean;
    expires_at: string | null;
  }

  let filters = $state<ContentFilter[]>([]);
  let loading = $state(true);

  // New filter form
  let newPhrase = $state('');
  let newAction = $state('warn');
  let newWholeWord = $state(false);
  let newContexts = $state(['home', 'public', 'notifications', 'thread']);
  let adding = $state(false);

  const allContexts = [
    { id: 'home', label: 'Home' },
    { id: 'public', label: 'Public' },
    { id: 'notifications', label: 'Notifications' },
    { id: 'thread', label: 'Threads' },
  ];

  onMount(async () => {
    try {
      filters = await api.get<ContentFilter[]>('/api/v1/accounts/filters');
    } catch { /* */ }
    finally { loading = false; }
  });

  async function addFilter() {
    if (!newPhrase.trim() || adding) return;
    adding = true;
    try {
      const f = await api.post<ContentFilter>('/api/v1/accounts/filters', {
        phrase: newPhrase,
        action: newAction,
        whole_word: newWholeWord,
        context: newContexts,
      });
      filters = [f, ...filters];
      newPhrase = '';
      newWholeWord = false;
      reloadFilters();
      addToast('Filter added', 'success');
    } catch {
      addToast('Failed to add filter', 'error');
    } finally { adding = false; }
  }

  async function removeFilter(id: string) {
    try {
      await api.delete(`/api/v1/accounts/filters/${id}`);
      filters = filters.filter(f => f.id !== id);
      reloadFilters();
      addToast('Filter removed', 'success');
    } catch {
      addToast('Failed to remove filter', 'error');
    }
  }

  function toggleContext(ctx: string) {
    if (newContexts.includes(ctx)) {
      newContexts = newContexts.filter(c => c !== ctx);
    } else {
      newContexts = [...newContexts, ctx];
    }
  }
</script>

<svelte:head>
  <title>Content Filters - Settings</title>
</svelte:head>

<div class="filters-page">
  <h1 class="stitch-title">Content Filters</h1>
  <p class="stitch-desc">Hide or warn about posts containing specific words or phrases.</p>

  <!-- Add filter form -->
  <div class="stitch-card">
    <h2 class="stitch-section-title">Add Filter</h2>
    <div class="filter-form">
      <div class="stitch-field">
        <label class="stitch-label" for="filter-phrase">Keyword or phrase</label>
        <input id="filter-phrase" type="text" class="stitch-input" bind:value={newPhrase} placeholder="e.g. spoiler, politics" />
      </div>

      <div class="stitch-field">
        <label class="stitch-label">Action</label>
        <div class="action-toggle">
          <button type="button" class="action-opt" class:active={newAction === 'warn'} onclick={() => newAction = 'warn'}>
            <span class="material-symbols-outlined" style="font-size: 16px">warning</span> Warn
          </button>
          <button type="button" class="action-opt" class:active={newAction === 'hide'} onclick={() => newAction = 'hide'}>
            <span class="material-symbols-outlined" style="font-size: 16px">visibility_off</span> Hide
          </button>
        </div>
      </div>

      <div class="stitch-field">
        <label class="stitch-label">Apply to</label>
        <div class="context-chips">
          {#each allContexts as ctx (ctx.id)}
            <button type="button" class="context-chip" class:active={newContexts.includes(ctx.id)} onclick={() => toggleContext(ctx.id)}>
              {ctx.label}
            </button>
          {/each}
        </div>
      </div>

      <label class="stitch-checkbox">
        <input type="checkbox" bind:checked={newWholeWord} />
        <span>Whole word only</span>
      </label>

      <button type="button" class="stitch-btn-primary" onclick={addFilter} disabled={!newPhrase.trim() || adding}>
        {adding ? 'Adding...' : 'Add filter'}
      </button>
    </div>
  </div>

  <!-- Existing filters -->
  <div class="stitch-card">
    <h2 class="stitch-section-title">Active Filters</h2>
    {#if loading}
      <div style="padding: 24px; text-align: center"><Spinner /></div>
    {:else if filters.length === 0}
      <p class="stitch-empty">No filters yet. Add one above.</p>
    {:else}
      <div class="filters-list">
        {#each filters as filter (filter.id)}
          <div class="filter-item">
            <div class="filter-info">
              <span class="filter-phrase">"{filter.phrase}"</span>
              <div class="filter-meta">
                <span class="filter-action-badge" class:badge-warn={filter.action === 'warn'} class:badge-hide={filter.action === 'hide'}>
                  {filter.action}
                </span>
                {#each filter.context as ctx}
                  <span class="filter-context-tag">{ctx}</span>
                {/each}
                {#if filter.whole_word}
                  <span class="filter-context-tag">whole word</span>
                {/if}
              </div>
            </div>
            <button type="button" class="filter-remove" onclick={() => removeFilter(filter.id)} aria-label="Remove filter">
              <span class="material-symbols-outlined" style="font-size: 18px">close</span>
            </button>
          </div>
        {/each}
      </div>
    {/if}
  </div>
</div>

<style>
  .filters-page { max-width: 600px; }
  .stitch-title { font-size: var(--text-2xl); font-weight: 700; margin-block-end: var(--space-2); }
  .stitch-desc { font-size: var(--text-sm); color: var(--color-text-secondary); margin-block-end: var(--space-6); }

  .stitch-card {
    background: var(--color-surface-raised, white);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-5);
    margin-block-end: var(--space-4);
  }

  .stitch-section-title { font-size: var(--text-base); font-weight: 600; margin-block-end: var(--space-4); }
  .stitch-empty { font-size: var(--text-sm); color: var(--color-text-tertiary); text-align: center; padding: var(--space-6); }

  .stitch-field { margin-block-end: var(--space-3); }
  .stitch-label { display: block; font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-secondary); margin-block-end: 6px; }
  .stitch-input { width: 100%; padding: 10px 14px; border: 1px solid var(--color-border); border-radius: 10px; font-size: 0.875rem; color: var(--color-text); background: var(--color-surface); }
  .stitch-input:focus { outline: none; border-color: var(--color-primary); box-shadow: 0 0 0 2px var(--color-primary-soft, rgba(0,128,128,0.1)); }

  .action-toggle { display: flex; gap: 8px; }
  .action-opt {
    display: flex; align-items: center; gap: 6px;
    padding: 8px 16px; border: 2px solid var(--color-border); border-radius: 10px;
    background: transparent; color: var(--color-text-secondary); font-size: 0.8125rem; font-weight: 600; cursor: pointer;
    transition: all 150ms ease;
  }
  .action-opt.active { border-color: var(--color-primary); color: var(--color-primary); background: var(--color-primary-soft, rgba(0,128,128,0.05)); }

  .context-chips { display: flex; flex-wrap: wrap; gap: 6px; }
  .context-chip {
    padding: 4px 12px; border: 1px solid var(--color-border); border-radius: 9999px;
    background: transparent; font-size: 0.75rem; font-weight: 600; color: var(--color-text-secondary); cursor: pointer;
    transition: all 150ms ease;
  }
  .context-chip.active { background: var(--color-primary); color: white; border-color: var(--color-primary); }

  .stitch-checkbox { display: flex; align-items: center; gap: 8px; font-size: 0.8125rem; color: var(--color-text-secondary); margin-block-end: var(--space-3); cursor: pointer; }
  .stitch-checkbox input { accent-color: var(--color-primary); }

  .stitch-btn-primary {
    padding: 10px 24px; background: var(--color-primary); color: white; border: none; border-radius: 9999px;
    font-size: 0.875rem; font-weight: 600; cursor: pointer;
  }
  .stitch-btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
  .stitch-btn-primary:hover:not(:disabled) { opacity: 0.9; }

  .filters-list { display: flex; flex-direction: column; gap: 8px; }
  .filter-item {
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
    padding: 10px 14px; background: var(--color-surface); border-radius: 10px;
  }

  .filter-phrase { font-size: 0.875rem; font-weight: 600; color: var(--color-text); }
  .filter-meta { display: flex; flex-wrap: wrap; gap: 4px; margin-block-start: 4px; }

  .filter-action-badge {
    font-size: 0.65rem; font-weight: 700; text-transform: uppercase; padding: 1px 6px; border-radius: 4px;
  }
  .badge-warn { background: rgba(245,158,11,0.15); color: #92400e; }
  .badge-hide { background: rgba(239,68,68,0.15); color: #dc2626; }

  .filter-context-tag { font-size: 0.65rem; color: var(--color-text-tertiary); background: var(--color-surface-container-low, #f0f0f0); padding: 1px 6px; border-radius: 4px; }

  .filter-remove {
    background: none; border: none; color: var(--color-text-tertiary); cursor: pointer; padding: 4px; border-radius: 50%;
    transition: background 150ms ease;
  }
  .filter-remove:hover { background: var(--color-danger-soft, rgba(239,68,68,0.1)); color: var(--color-danger); }
</style>

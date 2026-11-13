<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';

  interface CustomEmoji {
    id: string;
    shortcode: string;
    image_url: string;
    category: string | null;
    enabled: boolean;
    premium: boolean;
  }

  let emojis = $state<CustomEmoji[]>([]);
  let loading = $state(true);
  let saving = $state(false);

  let newShortcode = $state('');
  let newImageUrl = $state('');
  let newCategory = $state('');
  let newPremium = $state(false);

  let query = $state('');
  let visible = $derived.by(() => {
    const q = query.trim().toLowerCase();
    if (!q) return emojis;
    return emojis.filter((e) =>
      [e.shortcode, e.category].filter(Boolean).join(' ').toLowerCase().includes(q),
    );
  });

  async function load() {
    loading = true;
    try {
      emojis = await api.get<CustomEmoji[]>('/api/v1/admin/custom_emojis');
    } catch {
      addToast('Failed to load custom emojis', 'error');
    } finally {
      loading = false;
    }
  }

  async function create() {
    const sc = newShortcode.trim().toLowerCase().replace(/[^a-z0-9_]/g, '');
    if (!sc) {
      addToast('Shortcode is required (letters, numbers, underscores)', 'error');
      return;
    }
    if (!newImageUrl.trim()) {
      addToast('Image URL is required', 'error');
      return;
    }
    saving = true;
    try {
      const created = await api.post<CustomEmoji>('/api/v1/admin/custom_emojis', {
        shortcode: sc,
        image_url: newImageUrl.trim(),
        category: newCategory.trim() || null,
        premium: newPremium,
        enabled: true,
      });
      emojis = [...emojis, created];
      newShortcode = '';
      newImageUrl = '';
      newCategory = '';
      newPremium = false;
      addToast(`:${created.shortcode}: added`, 'success');
    } catch (e: unknown) {
      const err = e as { body?: { details?: Record<string, string[]> } };
      const detail = err?.body?.details
        ? Object.entries(err.body.details)
            .map(([k, v]) => `${k}: ${v.join(', ')}`)
            .join('; ')
        : '';
      addToast(detail || 'Failed to add emoji', 'error');
    } finally {
      saving = false;
    }
  }

  async function toggleEnabled(emoji: CustomEmoji) {
    try {
      const updated = await api.patch<CustomEmoji>(
        `/api/v1/admin/custom_emojis/${emoji.id}`,
        { enabled: !emoji.enabled },
      );
      emojis = emojis.map((e) => (e.id === emoji.id ? updated : e));
    } catch {
      addToast('Failed to toggle', 'error');
    }
  }

  async function togglePremium(emoji: CustomEmoji) {
    try {
      const updated = await api.patch<CustomEmoji>(
        `/api/v1/admin/custom_emojis/${emoji.id}`,
        { premium: !emoji.premium },
      );
      emojis = emojis.map((e) => (e.id === emoji.id ? updated : e));
    } catch {
      addToast('Failed to toggle premium', 'error');
    }
  }

  async function remove(emoji: CustomEmoji) {
    if (
      !confirm(
        `Delete :${emoji.shortcode}:? Existing posts that already used it keep rendering; users just can't insert it any more.`,
      )
    )
      return;
    try {
      await api.delete(`/api/v1/admin/custom_emojis/${emoji.id}`);
      emojis = emojis.filter((e) => e.id !== emoji.id);
      addToast('Emoji removed', 'success');
    } catch {
      addToast('Failed to remove', 'error');
    }
  }

  onMount(load);
</script>

<svelte:head>
  <title>Custom Emojis - Admin</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <div>
      <h1>Custom Emojis</h1>
      <p class="page-subtitle">
        Instance-wide emoji catalog. Anyone can insert these as <code>:shortcode:</code> in posts;
        marking one as premium restricts insertion to paid tiers.
      </p>
    </div>
  </header>

  <section class="add-form">
    <h2>Add emoji</h2>
    <div class="add-grid">
      <label class="field">
        <span>Shortcode</span>
        <input
          type="text"
          bind:value={newShortcode}
          placeholder="party_parrot"
          maxlength="32"
        />
      </label>
      <label class="field field-wide">
        <span>Image URL</span>
        <input
          type="url"
          bind:value={newImageUrl}
          placeholder="https://example.com/parrot.gif"
        />
      </label>
      <label class="field">
        <span>Category</span>
        <input
          type="text"
          bind:value={newCategory}
          placeholder="(optional)"
        />
      </label>
      <label class="field-checkbox">
        <input type="checkbox" bind:checked={newPremium} />
        <span>Premium-only</span>
      </label>
      <button type="button" class="btn-primary" onclick={create} disabled={saving}>
        {saving ? 'Adding…' : 'Add emoji'}
      </button>
    </div>
  </section>

  <section class="list-section">
    <header class="list-header">
      <h2>Catalog ({emojis.length})</h2>
      <input
        type="search"
        class="search-input"
        placeholder="Search emojis…"
        bind:value={query}
      />
    </header>

    {#if loading}
      <p class="empty">Loading…</p>
    {:else if visible.length === 0}
      <p class="empty">{emojis.length === 0 ? 'No custom emojis yet.' : 'No matches.'}</p>
    {:else}
      <ul class="emoji-grid">
        {#each visible as e (e.id)}
          <li class="emoji-card" class:disabled={!e.enabled}>
            <img class="emoji-img" src={e.image_url} alt={`:${e.shortcode}:`} />
            <div class="emoji-meta">
              <code class="emoji-shortcode">:{e.shortcode}:</code>
              {#if e.category}
                <span class="emoji-category">{e.category}</span>
              {/if}
              {#if e.premium}
                <span class="emoji-premium">Premium</span>
              {/if}
              {#if !e.enabled}
                <span class="emoji-disabled-tag">Disabled</span>
              {/if}
            </div>
            <div class="emoji-actions">
              <button type="button" class="btn-mini" onclick={() => toggleEnabled(e)}>
                {e.enabled ? 'Disable' : 'Enable'}
              </button>
              <button type="button" class="btn-mini" onclick={() => togglePremium(e)}>
                {e.premium ? 'Make standard' : 'Make premium'}
              </button>
              <button type="button" class="btn-mini btn-mini-danger" onclick={() => remove(e)}>
                Delete
              </button>
            </div>
          </li>
        {/each}
      </ul>
    {/if}
  </section>
</div>

<style>
  .page {
    max-width: 960px;
    margin: 0 auto;
    padding: var(--space-4);
  }

  .page-header h1 {
    font-size: var(--text-xl);
    font-weight: 700;
    margin: 0 0 var(--space-1);
  }

  .page-subtitle {
    color: var(--color-text-secondary);
    margin: 0;
    font-size: var(--text-sm);
  }

  .page-subtitle code {
    background: var(--color-surface);
    padding: 1px 6px;
    border-radius: 4px;
  }

  .add-form,
  .list-section {
    margin-block-start: var(--space-6);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    padding: var(--space-4);
  }

  .add-form h2,
  .list-section h2 {
    font-size: var(--text-base);
    font-weight: 700;
    margin: 0 0 var(--space-3);
  }

  .add-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr) auto auto;
    gap: var(--space-3);
    align-items: end;
  }

  .field-wide {
    grid-column: span 2;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .field span {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
  }

  .field input {
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-bg);
    color: var(--color-text);
    font-size: var(--text-sm);
  }

  .field input:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .field-checkbox {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: var(--text-sm);
  }

  .btn-primary {
    background: var(--color-primary);
    color: var(--color-on-primary);
    border: 0;
    padding: var(--space-2) var(--space-4);
    border-radius: var(--radius-md);
    font-weight: 600;
    cursor: pointer;
  }

  .btn-primary:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .list-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    margin-block-end: var(--space-3);
  }

  .search-input {
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-bg);
    color: var(--color-text);
    font-size: var(--text-sm);
    max-width: 240px;
  }

  .empty {
    color: var(--color-text-tertiary);
    text-align: center;
    padding: var(--space-6);
  }

  .emoji-grid {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
    gap: var(--space-3);
  }

  .emoji-card {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding: var(--space-3);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
  }

  .emoji-card.disabled {
    opacity: 0.55;
  }

  .emoji-img {
    width: 48px;
    height: 48px;
    object-fit: contain;
  }

  .emoji-meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-2);
  }

  .emoji-shortcode {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
  }

  .emoji-category,
  .emoji-premium,
  .emoji-disabled-tag {
    font-size: var(--text-xs);
    padding: 2px 8px;
    border-radius: 999px;
  }

  .emoji-category {
    background: var(--color-surface-container);
    color: var(--color-text-secondary);
  }

  .emoji-premium {
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-weight: 700;
  }

  .emoji-disabled-tag {
    background: var(--color-danger-soft);
    color: var(--color-danger);
    font-weight: 600;
  }

  .emoji-actions {
    display: flex;
    gap: var(--space-2);
    flex-wrap: wrap;
  }

  .btn-mini {
    background: var(--color-surface-container);
    border: 1px solid var(--color-border);
    color: var(--color-text);
    padding: 4px 10px;
    border-radius: var(--radius-sm);
    font-size: var(--text-xs);
    font-weight: 600;
    cursor: pointer;
  }

  .btn-mini:hover {
    background: var(--color-surface);
  }

  .btn-mini-danger {
    color: var(--color-danger);
    border-color: var(--color-danger-border);
  }

  .btn-mini-danger:hover {
    background: var(--color-danger-soft);
  }
</style>

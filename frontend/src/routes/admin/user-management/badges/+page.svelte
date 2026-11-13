<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { uploadMedia } from '$lib/api/media.js';
  import { addToast } from '$lib/stores/toast.js';

  interface CustomBadge {
    id: string;
    slug: string;
    name: string;
    description: string | null;
    image_url: string;
    sort_order: number;
    enabled: boolean;
    created_at?: string;
  }

  let badges = $state<CustomBadge[]>([]);
  let loading = $state(true);
  let saving = $state(false);
  let uploading = $state(false);
  let uploadProgress = $state(0);

  let newSlug = $state('');
  let newName = $state('');
  let newDescription = $state('');
  let newImageUrl = $state('');
  let newSortOrder = $state(0);

  let query = $state('');
  let visible = $derived.by(() => {
    const q = query.trim().toLowerCase();
    if (!q) return badges;
    return badges.filter((b) =>
      [b.slug, b.name, b.description].filter(Boolean).join(' ').toLowerCase().includes(q),
    );
  });

  async function load() {
    loading = true;
    try {
      badges = await api.get<CustomBadge[]>('/api/v1/admin/custom_badges');
    } catch {
      addToast('Failed to load badges', 'error');
    } finally {
      loading = false;
    }
  }

  // Upload artwork through the regular media pipeline so it goes
  // through size/AV checks and ends up on the same storage as the
  // rest of the site's media. We then pass the returned URL to the
  // badge POST.
  async function handleFile(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    uploading = true;
    uploadProgress = 0;
    try {
      const media = await uploadMedia(file, undefined, (frac) => {
        uploadProgress = Math.round(frac * 100);
      });
      newImageUrl = media.url || media.preview_url || '';
      addToast('Artwork uploaded', 'success');
    } catch (e: any) {
      addToast(e?.body?.error_description || 'Upload failed', 'error');
    } finally {
      uploading = false;
      input.value = '';
    }
  }

  async function create() {
    const slug = newSlug.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '');
    if (!slug) {
      addToast('Slug is required (letters, numbers, dashes, or underscores)', 'error');
      return;
    }
    if (!newName.trim()) {
      addToast('Name is required', 'error');
      return;
    }
    if (!newImageUrl.trim()) {
      addToast('Upload artwork or paste an image URL', 'error');
      return;
    }
    saving = true;
    try {
      const created = await api.post<CustomBadge>('/api/v1/admin/custom_badges', {
        slug,
        name: newName.trim(),
        description: newDescription.trim() || null,
        image_url: newImageUrl.trim(),
        sort_order: Number.isFinite(newSortOrder) ? newSortOrder : 0,
        enabled: true,
      });
      badges = [...badges, created];
      newSlug = '';
      newName = '';
      newDescription = '';
      newImageUrl = '';
      newSortOrder = 0;
      addToast(`Badge "${created.name}" added`, 'success');
    } catch (e: any) {
      const detail = e?.body?.details
        ? Object.entries(e.body.details as Record<string, string[]>)
            .map(([k, v]) => `${k}: ${v.join(', ')}`)
            .join('; ')
        : '';
      addToast(detail || 'Failed to add badge', 'error');
    } finally {
      saving = false;
    }
  }

  async function toggleEnabled(b: CustomBadge) {
    try {
      const updated = await api.patch<CustomBadge>(
        `/api/v1/admin/custom_badges/${b.id}`,
        { enabled: !b.enabled },
      );
      badges = badges.map((x) => (x.id === b.id ? updated : x));
    } catch {
      addToast('Failed to toggle', 'error');
    }
  }

  async function remove(b: CustomBadge) {
    if (!confirm(`Delete badge "${b.name}"? Anyone currently displaying it will lose it immediately.`)) return;
    try {
      await api.delete(`/api/v1/admin/custom_badges/${b.id}`);
      badges = badges.filter((x) => x.id !== b.id);
      addToast('Badge removed', 'success');
    } catch {
      addToast('Failed to remove', 'error');
    }
  }

  onMount(load);
</script>

<svelte:head>
  <title>Custom Badges - Admin</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <h1>Custom Badges</h1>
    <p class="page-subtitle">
      Upload extra badges on top of the built-in role/verification ones.
      Built-in badges (Owner, Admin, Mod, Verified tiers, Bot) keep their
      hardcoded artwork; this catalog is for instance-defined extras.
    </p>
  </header>

  <section class="add-form">
    <h2>Add badge</h2>
    <div class="add-grid">
      <label class="field">
        <span>Slug</span>
        <input type="text" bind:value={newSlug} placeholder="early_supporter" maxlength="40" />
      </label>
      <label class="field">
        <span>Name</span>
        <input type="text" bind:value={newName} placeholder="Early Supporter" maxlength="60" />
      </label>
      <label class="field field-wide">
        <span>Description</span>
        <input type="text" bind:value={newDescription} placeholder="(optional, max 280 chars)" maxlength="280" />
      </label>
      <label class="field">
        <span>Sort order</span>
        <input type="number" bind:value={newSortOrder} min="0" max="999" />
      </label>

      <div class="upload-block field-wide">
        <span class="field-label">Artwork</span>
        <div class="upload-row">
          <label class="upload-btn">
            <input type="file" accept="image/svg+xml,image/png,image/webp,image/jpeg" onchange={handleFile} hidden />
            <span>{uploading ? `Uploading… ${uploadProgress}%` : 'Upload image'}</span>
          </label>
          <input
            type="url"
            class="image-url-input"
            bind:value={newImageUrl}
            placeholder="…or paste an image URL"
          />
          {#if newImageUrl}
            <img src={newImageUrl} alt="badge preview" class="badge-preview" />
          {/if}
        </div>
      </div>

      <button type="button" class="btn-primary" onclick={create} disabled={saving || uploading}>
        {saving ? 'Adding…' : 'Add badge'}
      </button>
    </div>
  </section>

  <section class="list-section">
    <header class="list-header">
      <h2>Catalog ({badges.length})</h2>
      <input type="search" class="search-input" placeholder="Search badges…" bind:value={query} />
    </header>

    {#if loading}
      <p class="empty">Loading…</p>
    {:else if visible.length === 0}
      <p class="empty">{badges.length === 0 ? 'No custom badges yet.' : 'No matches.'}</p>
    {:else}
      <ul class="badge-grid">
        {#each visible as b (b.id)}
          <li class="badge-card" class:disabled={!b.enabled}>
            <img class="badge-img" src={b.image_url} alt={b.name} />
            <div class="badge-meta">
              <strong class="badge-name">{b.name}</strong>
              <code class="badge-slug">:{b.slug}:</code>
              {#if b.description}
                <span class="badge-desc">{b.description}</span>
              {/if}
              {#if !b.enabled}
                <span class="badge-disabled-tag">Disabled</span>
              {/if}
            </div>
            <div class="badge-actions">
              <button type="button" class="btn-mini" onclick={() => toggleEnabled(b)}>
                {b.enabled ? 'Disable' : 'Enable'}
              </button>
              <button type="button" class="btn-mini btn-mini-danger" onclick={() => remove(b)}>
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
    /* Match the other tabs in the User-management section: content
       aligns to the start of the layout column rather than centering
       inside the card so all tabs visually agree. */
    margin: 0;
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
    grid-template-columns: repeat(3, 1fr) auto;
    gap: var(--space-3);
    align-items: end;
  }

  .field-wide {
    grid-column: 1 / -1;
  }

  .field,
  .upload-block {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .field span,
  .field-label {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
  }

  .field input,
  .image-url-input {
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-bg);
    color: var(--color-text);
    font-size: var(--text-sm);
  }

  .field input:focus,
  .image-url-input:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .upload-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .upload-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface-container);
    border: 1px dashed var(--color-border);
    border-radius: var(--radius-md);
    cursor: pointer;
    font-size: var(--text-sm);
    white-space: nowrap;
  }

  .upload-btn:hover {
    background: var(--color-surface);
  }

  .image-url-input {
    flex: 1;
  }

  .badge-preview {
    width: 36px;
    height: 36px;
    object-fit: contain;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-bg);
    padding: 2px;
  }

  .btn-primary {
    background: var(--color-primary);
    color: var(--color-text-inverse, var(--color-on-primary));
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

  .badge-grid {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: var(--space-3);
  }

  .badge-card {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding: var(--space-3);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
  }

  .badge-card.disabled {
    opacity: 0.55;
  }

  .badge-img {
    width: 56px;
    height: 56px;
    object-fit: contain;
  }

  .badge-meta {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .badge-name {
    font-size: var(--text-sm);
    font-weight: 700;
  }

  .badge-slug {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .badge-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .badge-disabled-tag {
    align-self: flex-start;
    margin-block-start: 4px;
    font-size: var(--text-xs);
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--color-danger-soft);
    color: var(--color-danger);
    font-weight: 600;
  }

  .badge-actions {
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

  @media (max-width: 720px) {
    .add-grid {
      grid-template-columns: 1fr;
    }
  }
</style>

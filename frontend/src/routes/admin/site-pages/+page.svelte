<script lang="ts">
  import { onMount } from 'svelte';
  import { marked } from 'marked';
  import { addToast } from '$lib/stores/toast.js';
  import { getSitePages, updateSitePage, seedSitePages } from '$lib/api/admin.js';
  import type { SitePage } from '$lib/api/admin.js';

  let pages: SitePage[] = $state([]);
  let loading = $state(true);
  let selectedPage: SitePage | null = $state(null);
  let editMarkdown = $state('');
  let editTitle = $state('');
  let editPublished = $state(false);
  let saving = $state(false);
  let previewMode = $state(false);

  let previewHtml = $derived(editMarkdown ? marked(editMarkdown) as string : '');

  onMount(async () => {
    try {
      pages = await getSitePages();
      if (pages.length === 0) {
        pages = await seedSitePages();
      }
    } catch {
      addToast('Failed to load site pages', 'error');
    } finally {
      loading = false;
    }
  });

  function selectPage(page: SitePage) {
    selectedPage = page;
    editMarkdown = page.body_markdown;
    editTitle = page.title;
    editPublished = page.published;
    previewMode = false;
  }

  async function handleSave() {
    if (!selectedPage) return;
    saving = true;
    try {
      const updated = await updateSitePage(selectedPage.id, {
        title: editTitle,
        body_markdown: editMarkdown,
        published: editPublished
      });
      pages = pages.map(p => p.id === updated.id ? updated : p);
      selectedPage = updated;
      addToast('Page saved', 'success');
    } catch {
      addToast('Failed to save page', 'error');
    } finally {
      saving = false;
    }
  }

  const slugLabels: Record<string, string> = {
    privacy: 'Privacy Policy',
    terms: 'Terms of Service',
    about: 'About This Server'
  };

  const slugIcons: Record<string, string> = {
    privacy: 'M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z',
    terms: 'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z',
    about: 'M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z'
  };
</script>

<svelte:head>
  <title>Site Pages - Admin</title>
</svelte:head>

<div class="sp-layout">
  <div class="sp-header">
    <h2 class="sp-title">Site Pages</h2>
    <p class="sp-subtitle">Manage your privacy policy, terms of service, and about page. Write in Markdown.</p>
  </div>

  {#if loading}
    <div class="sp-loading">Loading...</div>
  {:else}
    <div class="sp-body">
      <!-- Page list -->
      <div class="sp-list">
        {#each pages as page (page.id)}
          <button
            class="sp-list-item"
            class:sp-list-item-active={selectedPage?.id === page.id}
            onclick={() => selectPage(page)}
          >
            <svg class="sp-list-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d={slugIcons[page.slug] || slugIcons.about} />
            </svg>
            <div class="sp-list-info">
              <div class="sp-list-name">{slugLabels[page.slug] || page.title}</div>
              <div class="sp-list-meta">
                /{page.slug}
                {#if page.published}
                  <span class="sp-badge sp-badge-published">Published</span>
                {:else}
                  <span class="sp-badge sp-badge-draft">Draft</span>
                {/if}
              </div>
            </div>
          </button>
        {/each}
      </div>

      <!-- Editor -->
      {#if selectedPage}
        <div class="sp-editor">
          <div class="sp-editor-toolbar">
            <div class="sp-editor-tabs">
              <button
                class="sp-tab"
                class:sp-tab-active={!previewMode}
                onclick={() => previewMode = false}
              >
                Edit
              </button>
              <button
                class="sp-tab"
                class:sp-tab-active={previewMode}
                onclick={() => previewMode = true}
              >
                Preview
              </button>
            </div>

            <div class="sp-editor-actions">
              <label class="sp-toggle-label">
                <input type="checkbox" bind:checked={editPublished} class="sp-toggle" />
                Published
              </label>
              <button class="sp-save-btn" onclick={handleSave} disabled={saving}>
                {saving ? 'Saving...' : 'Save'}
              </button>
            </div>
          </div>

          <div class="sp-editor-title-row">
            <input
              type="text"
              class="sp-title-input"
              bind:value={editTitle}
              placeholder="Page title"
            />
          </div>

          {#if previewMode}
            <div class="sp-preview prose">
              {#if previewHtml}
                {@html previewHtml}
              {:else}
                <p class="sp-empty">No content yet. Switch to Edit to start writing.</p>
              {/if}
            </div>
          {:else}
            <textarea
              class="sp-textarea"
              bind:value={editMarkdown}
              placeholder="Write your page content in Markdown...

# Heading 1
## Heading 2
### Heading 3

Regular paragraph text with **bold** and *italic*.

- List item one
- List item two

[Link text](https://example.com)"
              spellcheck="true"
            ></textarea>
          {/if}
        </div>
      {:else}
        <div class="sp-empty-state">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" opacity="0.3">
            <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" />
            <polyline points="14 2 14 8 20 8" />
            <line x1="16" y1="13" x2="8" y2="13" />
            <line x1="16" y1="17" x2="8" y2="17" />
            <polyline points="10 9 9 9 8 9" />
          </svg>
          <p>Select a page to edit</p>
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .sp-layout {
    padding: var(--space-6);
    max-width: 1100px;
  }

  .sp-header {
    margin-block-end: var(--space-6);
  }

  .sp-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-1);
  }

  .sp-subtitle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .sp-loading {
    padding: var(--space-8);
    text-align: center;
    color: var(--color-text-secondary);
  }

  .sp-body {
    display: flex;
    gap: var(--space-6);
    align-items: flex-start;
  }

  /* Page list */
  .sp-list {
    width: 240px;
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .sp-list-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    background: var(--color-surface-raised);
    cursor: pointer;
    text-align: left;
    transition: background var(--transition-fast), border-color var(--transition-fast);
  }

  .sp-list-item:hover {
    background: var(--color-surface);
  }

  .sp-list-item-active {
    border-color: var(--color-primary);
    background: var(--color-primary-soft);
  }

  .sp-list-icon {
    flex-shrink: 0;
    color: var(--color-text-secondary);
  }

  .sp-list-item-active .sp-list-icon {
    color: var(--color-primary);
  }

  .sp-list-info {
    min-width: 0;
  }

  .sp-list-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .sp-list-meta {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin-block-start: 2px;
  }

  .sp-badge {
    font-size: 0.625rem;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: var(--radius-full);
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .sp-badge-published {
    background: var(--color-success-soft);
    color: var(--color-success);
  }

  .sp-badge-draft {
    background: var(--color-warning-soft);
    color: var(--color-warning);
  }

  /* Editor */
  .sp-editor {
    flex: 1;
    min-width: 0;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    background: var(--color-surface-raised);
    overflow: hidden;
  }

  .sp-editor-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-3) var(--space-4);
    border-block-end: 1px solid var(--color-border);
    background: var(--color-surface);
  }

  .sp-editor-tabs {
    display: flex;
    gap: 2px;
    background: var(--color-border);
    border-radius: var(--radius-md);
    padding: 2px;
  }

  .sp-tab {
    padding: var(--space-1) var(--space-3);
    border: none;
    border-radius: var(--radius-sm);
    background: transparent;
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text-secondary);
    cursor: pointer;
  }

  .sp-tab-active {
    background: var(--color-surface-raised);
    color: var(--color-text);
    box-shadow: var(--shadow-sm);
  }

  .sp-editor-actions {
    display: flex;
    align-items: center;
    gap: var(--space-4);
  }

  .sp-toggle-label {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    cursor: pointer;
  }

  .sp-toggle {
    width: 16px;
    height: 16px;
    accent-color: var(--color-primary);
  }

  .sp-save-btn {
    padding: var(--space-1) var(--space-4);
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border: none;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .sp-save-btn:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .sp-save-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .sp-editor-title-row {
    padding: var(--space-3) var(--space-4);
    border-block-end: 1px solid var(--color-border);
  }

  .sp-title-input {
    width: 100%;
    border: none;
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
    background: transparent;
    outline: none;
  }

  .sp-title-input::placeholder {
    color: var(--color-text-tertiary);
  }

  .sp-textarea {
    display: block;
    width: 100%;
    min-height: 500px;
    padding: var(--space-4);
    border: none;
    font-family: var(--font-mono, monospace);
    font-size: var(--text-sm);
    line-height: 1.7;
    color: var(--color-text);
    background: transparent;
    resize: vertical;
    outline: none;
  }

  .sp-textarea::placeholder {
    color: var(--color-text-tertiary);
  }

  .sp-preview {
    padding: var(--space-6);
    min-height: 500px;
    font-size: var(--text-sm);
    line-height: 1.8;
    color: var(--color-text);
  }

  .sp-preview :global(h1) {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin: var(--space-6) 0 var(--space-3);
    color: var(--color-text);
  }

  .sp-preview :global(h2) {
    font-size: var(--text-xl);
    font-weight: 600;
    margin: var(--space-5) 0 var(--space-2);
    color: var(--color-text);
  }

  .sp-preview :global(h3) {
    font-size: var(--text-lg);
    font-weight: 600;
    margin: var(--space-4) 0 var(--space-2);
    color: var(--color-text);
  }

  .sp-preview :global(p) {
    margin: var(--space-3) 0;
  }

  .sp-preview :global(ul),
  .sp-preview :global(ol) {
    margin: var(--space-3) 0;
    padding-inline-start: var(--space-6);
  }

  .sp-preview :global(li) {
    margin: var(--space-1) 0;
  }

  .sp-preview :global(a) {
    color: var(--color-primary);
  }

  .sp-preview :global(code) {
    background: var(--color-surface);
    padding: 2px 6px;
    border-radius: var(--radius-sm);
    font-size: 0.9em;
  }

  .sp-preview :global(strong) {
    font-weight: 600;
  }

  .sp-empty {
    color: var(--color-text-tertiary);
    font-style: italic;
  }

  .sp-empty-state {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: var(--space-16);
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    gap: var(--space-3);
  }

  @media (max-width: 768px) {
    .sp-body {
      flex-direction: column;
    }

    .sp-list {
      width: 100%;
      flex-direction: row;
      overflow-x: auto;
    }

    .sp-list-item {
      white-space: nowrap;
    }
  }
</style>

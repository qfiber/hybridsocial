<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface ExportEntry {
    id: string;
    type: string;
    status: string;
    created_at: string;
    download_url: string | null;
  }

  let exports: ExportEntry[] = $state([]);
  let exportsLoading = $state(true);
  let exportingFollows = $state(false);
  let exportingBlocks = $state(false);
  let importing = $state(false);
  let importFile: File | null = $state(null);
  let fileInput: HTMLInputElement | undefined = $state();

  onMount(async () => {
    await loadExports();
  });

  async function loadExports() {
    try {
      const res = await api.get<{ data: ExportEntry[] }>('/api/v1/export');
      exports = res.data;
    } catch {
      addToast('Failed to load exports', 'error');
    } finally {
      exportsLoading = false;
    }
  }

  async function handleExport(type: string) {
    if (type === 'follows') exportingFollows = true;
    else exportingBlocks = true;

    try {
      const res = await api.post<ExportEntry>('/api/v1/export', { type });
      exports = [res, ...exports];
      addToast(`Export of ${type} started`, 'success');
    } catch {
      addToast(`Failed to export ${type}`, 'error');
    } finally {
      if (type === 'follows') exportingFollows = false;
      else exportingBlocks = false;
    }
  }

  function handleFileSelect(e: Event) {
    const input = e.target as HTMLInputElement;
    importFile = input.files?.[0] ?? null;
  }

  async function handleImport(e: Event) {
    e.preventDefault();
    if (!importFile) return;

    importing = true;
    try {
      await api.upload('/api/v1/import', importFile);
      addToast('Import started successfully', 'success');
      importFile = null;
      if (fileInput) fileInput.value = '';
    } catch {
      addToast('Failed to import data', 'error');
    } finally {
      importing = false;
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  function formatType(type: string): string {
    return type.charAt(0).toUpperCase() + type.slice(1);
  }

  function statusColor(status: string): string {
    switch (status) {
      case 'completed': return '#16a34a';
      case 'pending': case 'processing': return '#d97706';
      case 'failed': return '#dc2626';
      default: return '#6b7280';
    }
  }
</script>

<div class="stitch-settings">
  <div class="stitch-settings-header">
    <h1 class="stitch-settings-title">Import & Export</h1>
    <p class="stitch-settings-subtitle">Export your data or import from another account</p>
  </div>

  <!-- Export -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Export Data</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        <p class="stitch-description">
          Export your follows or blocks as CSV files. You can use these to migrate to another instance or as a backup.
        </p>

        <div class="stitch-export-buttons">
          <button
            class="stitch-btn-outline"
            onclick={() => handleExport('follows')}
            disabled={exportingFollows}
          >
            {#if exportingFollows}
              <Spinner size={14} />
            {/if}
            Export Follows
          </button>
          <button
            class="stitch-btn-outline"
            onclick={() => handleExport('blocks')}
            disabled={exportingBlocks}
          >
            {#if exportingBlocks}
              <Spinner size={14} />
            {/if}
            Export Blocks
          </button>
        </div>

        {#if exportsLoading}
          <div class="stitch-loading"><Spinner size={20} /> Loading exports...</div>
        {:else if exports.length > 0}
          <div class="stitch-list">
            {#each exports as entry (entry.id)}
              <div class="stitch-list-item">
                <div class="stitch-list-info">
                  <div class="stitch-list-name">{formatType(entry.type)}</div>
                  <div class="stitch-list-meta-row">
                    <span class="stitch-export-status" style="color: {statusColor(entry.status)}">{entry.status}</span>
                    <span class="stitch-list-dot">&middot;</span>
                    <span>{formatDate(entry.created_at)}</span>
                  </div>
                </div>
                {#if entry.download_url && entry.status === 'completed'}
                  <a
                    href={entry.download_url}
                    class="stitch-btn-primary stitch-btn-sm"
                    download
                  >
                    Download
                  </a>
                {/if}
              </div>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  </section>

  <!-- Import -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Import Data</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        <p class="stitch-description">
          Import a CSV file of follows, blocks, or mutes from another instance. The file should contain one account per line in handle@domain format.
        </p>

        <form class="stitch-import-form" onsubmit={handleImport}>
          <div class="stitch-field">
            <label class="stitch-label" for="import-file">CSV FILE</label>
            <input
              bind:this={fileInput}
              id="import-file"
              type="file"
              class="stitch-file-input"
              accept=".csv,text/csv"
              onchange={handleFileSelect}
              required
            />
          </div>

          <div class="stitch-actions">
            <button class="stitch-btn-primary" type="submit" disabled={importing || !importFile}>
              {#if importing}
                <Spinner size={16} color="#fff" />
              {/if}
              Import
            </button>
          </div>
        </form>
      </div>
    </div>
  </section>
</div>

<style>
  .stitch-settings {
    max-width: 720px;
  }

  .stitch-settings-header {
    margin-block-end: 32px;
  }

  .stitch-settings-title {
    font-family: 'Manrope', var(--font-sans);
    font-size: 1.875rem;
    font-weight: 800;
    letter-spacing: -0.025em;
    color: var(--color-text);
    margin: 0;
  }

  .stitch-settings-subtitle {
    font-size: 0.875rem;
    color: #6b7280;
    margin-block-start: 4px;
  }

  .stitch-section {
    margin-block-end: 24px;
  }

  .stitch-section-heading {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-block-end: 16px;
  }

  .stitch-section-icon {
    color: var(--color-primary);
    display: flex;
    align-items: center;
  }

  .stitch-section-title {
    font-size: 1.125rem;
    font-weight: 700;
    color: var(--color-text);
    margin: 0;
  }

  .stitch-section-content {
    background: #f2f4f5;
    border-radius: 16px;
    overflow: hidden;
  }

  .stitch-form {
    padding: 24px 32px 32px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .stitch-description {
    font-size: 0.875rem;
    color: #6b7280;
    line-height: 1.5;
  }

  .stitch-loading {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.875rem;
    color: #6b7280;
  }

  .stitch-export-buttons {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
  }

  .stitch-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .stitch-label {
    font-size: 0.6875rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #6b7280;
    margin-inline-start: 4px;
  }

  .stitch-file-input {
    display: block;
    width: 100%;
    padding: 12px 16px;
    background: #e6e8e9;
    border: none;
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    cursor: pointer;
  }

  .stitch-file-input::file-selector-button {
    padding: 6px 16px;
    background: var(--color-primary);
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
    margin-inline-end: 12px;
  }

  .stitch-import-form {
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .stitch-list {
    display: flex;
    flex-direction: column;
    gap: 1px;
    background: rgba(0, 0, 0, 0.06);
    border-radius: 12px;
    overflow: hidden;
  }

  .stitch-list-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 16px;
    background: #e6e8e9;
  }

  .stitch-list-info {
    flex: 1;
    min-width: 0;
  }

  .stitch-list-name {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-text);
  }

  .stitch-list-meta-row {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .stitch-list-dot {
    font-size: 0.75rem;
  }

  .stitch-export-status {
    font-weight: 600;
    text-transform: capitalize;
  }

  .stitch-actions {
    display: flex;
    justify-content: flex-end;
    gap: 12px;
    padding-block-start: 8px;
  }

  .stitch-btn-primary {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 28px;
    background: var(--color-primary);
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    text-decoration: none;
    box-shadow: 0 4px 14px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2);
    transition: background-color 0.15s ease, box-shadow 0.15s ease, transform 0.1s ease;
  }

  .stitch-btn-primary:hover:not(:disabled) {
    background: var(--color-primary-hover);
    box-shadow: 0 6px 20px rgba(var(--color-primary-rgb, 59, 130, 246), 0.3);
  }

  .stitch-btn-primary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .stitch-btn-outline {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 24px;
    background: transparent;
    border: 1.5px solid var(--color-primary);
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-primary);
    cursor: pointer;
    transition: background-color 0.15s ease;
  }

  .stitch-btn-outline:hover:not(:disabled) {
    background: rgba(var(--color-primary-rgb, 59, 130, 246), 0.06);
  }

  .stitch-btn-outline:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .stitch-btn-sm {
    padding: 6px 16px;
    font-size: 0.75rem;
  }

  @media (max-width: 640px) {
    .stitch-settings-title {
      font-size: 1.5rem;
    }

    .stitch-form {
      padding: 20px;
    }

    .stitch-export-buttons {
      flex-direction: column;
    }
  }
</style>

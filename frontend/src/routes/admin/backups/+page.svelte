<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getBackups, createBackup } from '$lib/api/admin.js';
  import type { Backup } from '$lib/api/types.js';

  let backups: Backup[] = $state([]);
  let loading = $state(true);
  let creating = $state(false);
  let passphrase = $state('');
  let showPassphrase = $state(false);

  function generatePassphrase(): string {
    const words = ['alpha','bravo','coral','delta','eagle','frost','grove','haven','ivory','jewel','karma','lunar','maple','noble','ocean','pearl','quest','ridge','solar','tiger','ultra','vivid','waker','xenon','yield','zephyr'];
    const parts: string[] = [];
    for (let i = 0; i < 4; i++) {
      parts.push(words[Math.floor(Math.random() * words.length)]);
    }
    // Add a random 2-digit number for entropy
    parts.push(String(Math.floor(Math.random() * 90) + 10));
    return parts.join('-');
  }

  onMount(async () => {
    try {
      backups = await getBackups();
    } catch {
      addToast('Failed to load backups', 'error');
    } finally {
      loading = false;
    }
  });

  async function handleCreate() {
    creating = true;
    try {
      const backup = await createBackup(passphrase || undefined);
      backups = [backup, ...backups];
      passphrase = '';
      addToast('Backup creation started', 'success');
    } catch {
      addToast('Failed to create backup', 'error');
    } finally {
      creating = false;
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  function formatSize(bytes: number | null | undefined): string {
    if (bytes == null) return '-';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  function statusIcon(status: string): string {
    switch (status) {
      case 'completed': return 'status-success';
      case 'in_progress': case 'pending': return 'status-pending';
      case 'failed': return 'status-failed';
      default: return '';
    }
  }
</script>

<svelte:head>
  <title>Backups - Admin</title>
</svelte:head>

<div class="backups-page">
  <h1 class="page-title">Backups</h1>

  <section class="card create-section">
    <h2 class="section-title">Create Backup</h2>
    <p class="section-desc">Create an encrypted backup of your instance data.</p>
    <form class="create-form" onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
      <div class="passphrase-field">
        <label for="passphrase" class="field-label">Encryption Passphrase (optional)</label>
        <div class="passphrase-input-row">
          <input
            id="passphrase"
            type={showPassphrase ? 'text' : 'password'}
            class="input"
            bind:value={passphrase}
            placeholder="Enter passphrase..."
          />
          <button
            class="btn btn-ghost btn-sm"
            type="button"
            onclick={() => (showPassphrase = !showPassphrase)}
          >{showPassphrase ? 'Hide' : 'Show'}</button>
          <button
            class="btn btn-ghost btn-sm"
            type="button"
            onclick={() => { passphrase = generatePassphrase(); showPassphrase = true; }}
          >Generate</button>
        </div>
      </div>
      <button class="btn btn-primary" type="submit" disabled={creating}>
        {creating ? 'Creating...' : 'Create Backup'}
      </button>
    </form>
  </section>

  <section class="card">
    <h2 class="section-title">Backup History</h2>

    {#if loading}
      {#each Array(3) as _}
        <div class="skeleton" style="height: 56px; margin-bottom: 8px"></div>
      {/each}
    {:else if backups.length === 0}
      <p class="empty-text">No backups found</p>
    {:else}
      <div class="backup-list">
        {#each backups as backup (backup.id)}
          <div class="backup-item">
            <div class="backup-info">
              <span class="backup-status {statusIcon(backup.status)}">
                {backup.status.replace(/_/g, ' ')}
              </span>
              <span class="backup-date">{formatDate(backup.created_at)}</span>
              <span class="backup-size">{formatSize(backup.file_size ?? backup.size)}</span>
            </div>
            <div class="backup-actions">
              {#if backup.status === 'completed' && backup.download_url}
                <a href={backup.download_url} class="btn btn-sm btn-outline" download>
                  Download
                </a>
              {:else if backup.status === 'in_progress' || backup.status === 'pending'}
                <span class="text-secondary" style="font-size: var(--text-xs)">Processing...</span>
              {:else if backup.status === 'failed'}
                <span class="text-danger" style="font-size: var(--text-xs)">Failed</span>
              {/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}
  </section>
</div>

<style>
  .backups-page {
    max-width: 800px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 600;
    margin-block-end: var(--space-2);
  }

  .section-desc {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-4);
  }

  .create-section {
    margin-block-end: var(--space-4);
  }

  .create-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    align-items: flex-start;
  }

  .passphrase-field {
    width: 100%;
    max-width: 400px;
  }

  .field-label {
    display: block;
    font-size: var(--text-sm);
    font-weight: 500;
    margin-block-end: var(--space-1);
  }

  .passphrase-input-row {
    display: flex;
    gap: var(--space-2);
  }

  .passphrase-input-row .input {
    flex: 1;
  }

  .backup-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .backup-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-3) var(--space-4);
    background: var(--color-surface);
    border-radius: var(--radius-md);
  }

  .backup-info {
    display: flex;
    align-items: center;
    gap: var(--space-4);
    font-size: var(--text-sm);
  }

  .backup-status {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .status-success {
    background: var(--color-success-soft);
    color: #166534;
  }

  .status-pending {
    background: var(--color-warning-soft);
    color: #92400e;
  }

  .status-failed {
    background: var(--color-danger-soft);
    color: #991b1b;
  }

  .backup-date {
    color: var(--color-text-secondary);
  }

  .backup-size {
    color: var(--color-text-tertiary);
    font-family: var(--font-mono);
    font-size: var(--text-xs);
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }
</style>

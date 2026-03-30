<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getRelays, addRelay, removeRelay } from '$lib/api/admin.js';
  import type { Relay } from '$lib/api/types.js';

  let relays: Relay[] = $state([]);
  let loading = $state(true);
  let newInboxUrl = $state('');
  let adding = $state(false);

  onMount(async () => {
    try {
      relays = await getRelays();
    } catch {
      addToast('Failed to load relays', 'error');
    } finally {
      loading = false;
    }
  });

  async function handleAdd() {
    if (!newInboxUrl.trim()) return;
    adding = true;
    try {
      const relay = await addRelay(newInboxUrl);
      relays = [...relays, relay];
      newInboxUrl = '';
      addToast('Relay added', 'success');
    } catch {
      addToast('Failed to add relay', 'error');
    } finally {
      adding = false;
    }
  }

  async function handleRemove(id: string) {
    try {
      await removeRelay(id);
      relays = relays.filter((r) => r.id !== id);
      addToast('Relay removed', 'success');
    } catch {
      addToast('Failed to remove relay', 'error');
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  }

  function statusClass(status: string): string {
    switch (status) {
      case 'accepted': return 'status-accepted';
      case 'pending': return 'status-pending';
      case 'rejected': return 'status-rejected';
      default: return '';
    }
  }
</script>

<svelte:head>
  <title>Relays - Admin</title>
</svelte:head>

<div class="relays-page">
  <h1 class="page-title">Relays</h1>
  <p class="page-desc">Relays are servers that help distribute content across the fediverse.</p>

  <section class="card add-section">
    <h2 class="section-title">Add Relay</h2>
    <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAdd(); }}>
      <input
        type="url"
        class="input"
        bind:value={newInboxUrl}
        placeholder="https://relay.example.com/inbox"
        required
      />
      <button class="btn btn-primary" type="submit" disabled={adding}>
        {adding ? 'Adding...' : 'Add Relay'}
      </button>
    </form>
  </section>

  <section class="card">
    <h2 class="section-title">Active Relays</h2>

    {#if loading}
      {#each Array(3) as _}
        <div class="skeleton" style="height: 48px; margin-bottom: 8px"></div>
      {/each}
    {:else if relays.length === 0}
      <p class="empty-text">No relays configured</p>
    {:else}
      <div class="relay-list">
        {#each relays as relay (relay.id)}
          <div class="relay-item">
            <div class="relay-info">
              <code class="relay-url">{relay.inbox_url}</code>
              <div class="relay-meta">
                <span class="relay-status {statusClass(relay.status)}">{relay.status}</span>
                {#if relay.created_at}
                  <span class="relay-date">Added {formatDate(relay.created_at)}</span>
                {/if}
              </div>
            </div>
            <button
              class="btn btn-sm btn-danger"
              type="button"
              onclick={() => handleRemove(relay.id)}
            >Remove</button>
          </div>
        {/each}
      </div>
    {/if}
  </section>
</div>

<style>
  .relays-page {
    max-width: 800px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-2);
  }

  .page-desc {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-6);
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 600;
    margin-block-end: var(--space-3);
  }

  .add-section {
    margin-block-end: var(--space-4);
  }

  .add-form {
    display: flex;
    gap: var(--space-2);
  }

  .add-form .input {
    flex: 1;
  }

  .relay-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .relay-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-3) var(--space-4);
    background: var(--color-surface);
    border-radius: var(--radius-md);
    gap: var(--space-3);
  }

  .relay-info {
    min-width: 0;
    flex: 1;
  }

  .relay-url {
    font-size: var(--text-sm);
    display: block;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .relay-meta {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    margin-block-start: var(--space-1);
  }

  .relay-status {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .status-accepted {
    background: var(--color-success-soft);
    color: #166534;
  }

  .status-pending {
    background: var(--color-warning-soft);
    color: #92400e;
  }

  .status-rejected {
    background: var(--color-danger-soft);
    color: #991b1b;
  }

  .relay-date {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }
</style>

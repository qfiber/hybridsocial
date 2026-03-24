<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getMediaHashBans, createMediaHashBan, deleteMediaHashBan } from '$lib/api/admin.js';
  import type { MediaHashBan } from '$lib/api/types.js';

  let bans: MediaHashBan[] = $state([]);
  let loading = $state(true);
  let newHash = $state('');
  let newHashType = $state<'md5' | 'sha256' | 'phash'>('sha256');
  let newDescription = $state('');

  onMount(async () => {
    await loadBans();
  });

  async function loadBans() {
    loading = true;
    try {
      bans = await getMediaHashBans();
    } catch {
      addToast('Failed to load media hash bans', 'error');
    } finally {
      loading = false;
    }
  }

  async function handleAdd() {
    if (!newHash.trim()) return;
    try {
      const ban = await createMediaHashBan({
        hash: newHash,
        hash_type: newHashType,
        description: newDescription || undefined
      });
      bans = [...bans, ban];
      newHash = '';
      newDescription = '';
      addToast('Media hash banned', 'success');
    } catch {
      addToast('Failed to ban media hash', 'error');
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteMediaHashBan(id);
      bans = bans.filter((b) => b.id !== id);
      addToast('Media hash ban removed', 'success');
    } catch {
      addToast('Failed to remove media hash ban', 'error');
    }
  }

  function truncateHash(hash: string): string {
    if (hash.length <= 16) return hash;
    return hash.slice(0, 8) + '...' + hash.slice(-8);
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    });
  }
</script>

<svelte:head>
  <title>Media Hashes - Admin</title>
</svelte:head>

<div class="media-hashes-page">
  <h1 class="page-title">Media Hash Bans</h1>

  <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAdd(); }}>
    <input class="input" type="text" bind:value={newHash} placeholder="Hash value..." required />
    <select class="input" bind:value={newHashType} style="width: 120px">
      <option value="sha256">SHA-256</option>
      <option value="md5">MD5</option>
      <option value="phash">pHash</option>
    </select>
    <input class="input" type="text" bind:value={newDescription} placeholder="Description (optional)" />
    <button class="btn btn-primary" type="submit">Ban Hash</button>
  </form>

  {#if loading}
    <div class="loading-area">
      <div class="skeleton" style="height: 50px"></div>
      <div class="skeleton" style="height: 50px"></div>
    </div>
  {:else}
    <div class="list-items">
      {#each bans as ban (ban.id)}
        <div class="list-item card">
          <div class="list-item-info">
            <code class="hash-value" title={ban.hash}>{truncateHash(ban.hash)}</code>
            <span class="badge-type">{ban.hash_type}</span>
            {#if ban.description}
              <span class="text-secondary">- {ban.description}</span>
            {/if}
            <span class="text-tertiary" style="font-size: var(--text-xs)">Added {formatDate(ban.created_at)}</span>
          </div>
          <button
            class="btn btn-sm btn-danger"
            type="button"
            onclick={() => handleDelete(ban.id)}
          >Remove</button>
        </div>
      {:else}
        <p class="empty-text">No media hash bans</p>
      {/each}
    </div>
  {/if}
</div>

<style>
  .media-hashes-page {
    max-width: 1100px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .add-form {
    display: flex;
    gap: var(--space-2);
    margin-block-end: var(--space-4);
    flex-wrap: wrap;
    align-items: flex-end;
  }

  .add-form .input {
    flex: 1;
    min-width: 150px;
  }

  .loading-area {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .list-items {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .list-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
  }

  .list-item-info {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
    font-size: var(--text-sm);
  }

  .hash-value {
    font-size: var(--text-sm);
    background: var(--color-surface);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
    cursor: help;
  }

  .badge-type {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    background: var(--color-info-soft);
    color: #1e40af;
    text-transform: uppercase;
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }
</style>

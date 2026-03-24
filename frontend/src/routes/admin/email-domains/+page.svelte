<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getEmailDomainBans, createEmailDomainBan, deleteEmailDomainBan } from '$lib/api/admin.js';
  import type { EmailDomainBan } from '$lib/api/types.js';

  let bans: EmailDomainBan[] = $state([]);
  let loading = $state(true);
  let newDomain = $state('');
  let newReason = $state('');

  onMount(async () => {
    await loadBans();
  });

  async function loadBans() {
    loading = true;
    try {
      bans = await getEmailDomainBans();
    } catch {
      addToast('Failed to load email domain bans', 'error');
    } finally {
      loading = false;
    }
  }

  async function handleAdd() {
    if (!newDomain.trim()) return;
    try {
      const ban = await createEmailDomainBan(newDomain, newReason || undefined);
      bans = [...bans, ban];
      newDomain = '';
      newReason = '';
      addToast('Email domain blocked', 'success');
    } catch {
      addToast('Failed to block email domain', 'error');
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteEmailDomainBan(id);
      bans = bans.filter((b) => b.id !== id);
      addToast('Email domain unblocked', 'success');
    } catch {
      addToast('Failed to unblock email domain', 'error');
    }
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
  <title>Email Domains - Admin</title>
</svelte:head>

<div class="email-domains-page">
  <h1 class="page-title">Email Domain Blocks</h1>

  <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAdd(); }}>
    <input class="input" type="text" bind:value={newDomain} placeholder="domain.example" required />
    <input class="input" type="text" bind:value={newReason} placeholder="Reason (optional)" />
    <button class="btn btn-primary" type="submit">Block Domain</button>
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
            <strong>{ban.domain}</strong>
            {#if ban.reason}
              <span class="text-secondary">- {ban.reason}</span>
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
        <p class="empty-text">No blocked email domains</p>
      {/each}
    </div>
  {/if}
</div>

<style>
  .email-domains-page {
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

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }
</style>

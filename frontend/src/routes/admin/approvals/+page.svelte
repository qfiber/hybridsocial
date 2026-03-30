<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface PendingAccount {
    id: string;
    handle: string;
    acct: string;
    display_name: string | null;
    avatar_url: string | null;
    created_at: string;
  }

  let accounts = $state<PendingAccount[]>([]);
  let loading = $state(true);

  onMount(async () => {
    try {
      const res = await api.get<{ data: PendingAccount[] }>('/api/v1/admin/pending_accounts');
      accounts = res.data || [];
    } catch {
      addToast('Failed to load pending accounts', 'error');
    } finally {
      loading = false;
    }
  });

  async function approve(id: string) {
    try {
      await api.post(`/api/v1/admin/pending_accounts/${id}/approve`);
      accounts = accounts.filter(a => a.id !== id);
      addToast('Account approved', 'success');
    } catch {
      addToast('Failed to approve account', 'error');
    }
  }

  async function reject(id: string) {
    try {
      await api.post(`/api/v1/admin/pending_accounts/${id}/reject`);
      accounts = accounts.filter(a => a.id !== id);
      addToast('Account rejected', 'success');
    } catch {
      addToast('Failed to reject account', 'error');
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  }
</script>

<svelte:head>
  <title>Pending Approvals - Admin</title>
</svelte:head>

<div class="approvals-page">
  <h1 class="page-title">Pending Approvals</h1>
  <p class="page-desc">Users who have confirmed their email and are waiting for admin approval.</p>

  {#if loading}
    <div class="loading-wrap"><Spinner /></div>
  {:else if accounts.length === 0}
    <div class="empty-state">
      <span class="material-symbols-outlined empty-icon">check_circle</span>
      <p>No accounts pending approval</p>
    </div>
  {:else}
    <div class="accounts-list">
      {#each accounts as account (account.id)}
        <div class="account-card">
          <div class="account-info">
            {#if account.avatar_url}
              <img src={account.avatar_url} alt="" class="account-avatar" />
            {:else}
              <div class="account-avatar account-avatar-placeholder">
                {(account.display_name || account.handle).charAt(0).toUpperCase()}
              </div>
            {/if}
            <div>
              <span class="account-name">{account.display_name || account.handle}</span>
              <span class="account-handle">@{account.acct || account.handle}</span>
              <span class="account-date">Registered {formatDate(account.created_at)}</span>
            </div>
          </div>
          <div class="account-actions">
            <button type="button" class="btn btn-sm btn-primary" onclick={() => approve(account.id)}>Approve</button>
            <button type="button" class="btn btn-sm btn-danger" onclick={() => reject(account.id)}>Reject</button>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .approvals-page { max-width: 800px; }
  .page-title { font-size: var(--text-2xl); font-weight: 700; margin-block-end: var(--space-2); }
  .page-desc { font-size: var(--text-sm); color: var(--color-text-secondary); margin-block-end: var(--space-6); }
  .loading-wrap { display: flex; justify-content: center; padding: var(--space-12); }

  .empty-state {
    text-align: center;
    padding: var(--space-12);
    color: var(--color-text-tertiary);
  }
  .empty-icon { font-size: 48px; display: block; margin: 0 auto var(--space-3); color: var(--color-success); }

  .accounts-list { display: flex; flex-direction: column; gap: var(--space-3); }

  .account-card {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-4);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
  }

  .account-info { display: flex; align-items: center; gap: var(--space-3); }

  .account-avatar {
    width: 40px; height: 40px; border-radius: 50%; object-fit: cover; flex-shrink: 0;
  }
  .account-avatar-placeholder {
    display: flex; align-items: center; justify-content: center;
    background: var(--color-primary-soft); color: var(--color-primary);
    font-weight: 700; font-size: 1rem;
  }

  .account-name { display: block; font-weight: 600; font-size: var(--text-sm); }
  .account-handle { display: block; font-size: var(--text-xs); color: var(--color-text-secondary); }
  .account-date { display: block; font-size: var(--text-xs); color: var(--color-text-tertiary); margin-block-start: 2px; }

  .account-actions { display: flex; gap: var(--space-2); }

  .btn-sm { padding: var(--space-1) var(--space-3); font-size: var(--text-xs); border-radius: var(--radius-md); cursor: pointer; font-weight: 600; border: none; }
  .btn-primary { background: var(--color-primary); color: white; }
  .btn-primary:hover { opacity: 0.9; }
  .btn-danger { background: var(--color-danger); color: white; }
  .btn-danger:hover { opacity: 0.9; }
</style>

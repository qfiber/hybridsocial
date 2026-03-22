<script lang="ts">
  import { onMount } from 'svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import DataTable from '$lib/components/admin/DataTable.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import {
    getKnownInstances,
    getFederationPolicies, createFederationPolicy, deleteFederationPolicy,
    getDeliveryQueueStats, retryDeliveryQueue
  } from '$lib/api/admin.js';
  import type { KnownInstance, FederationPolicy, DeliveryQueueStats } from '$lib/api/types.js';

  const tabs = [
    { id: 'instances', label: 'Known Instances' },
    { id: 'policies', label: 'Policies' },
    { id: 'delivery', label: 'Delivery Queue' }
  ];

  let activeTab = $state('instances');

  // Known Instances
  let instances: KnownInstance[] = $state([]);
  let instancesLoading = $state(true);
  let instanceSortKey = $state('last_activity_at');
  let instanceSortDir = $state<'asc' | 'desc'>('desc');

  let instanceRows = $derived(
    instances.map((i) => ({ ...i } as Record<string, unknown>))
  );

  const instanceColumns = [
    { key: 'domain', label: 'Domain', sortable: true },
    { key: 'software', label: 'Software' },
    { key: 'user_count', label: 'Users', sortable: true },
    { key: 'last_activity_at', label: 'Last Activity', sortable: true },
    { key: 'status', label: 'Status' }
  ];

  // Policies
  let policies: FederationPolicy[] = $state([]);
  let policiesLoading = $state(false);
  let newPolicyDomain = $state('');
  let newPolicyType = $state<'allow' | 'silence' | 'suspend'>('silence');
  let newPolicyReason = $state('');

  // Delivery Queue
  let deliveryStats: DeliveryQueueStats | null = $state(null);
  let deliveryLoading = $state(false);
  let retrying = $state(false);

  onMount(async () => {
    await loadInstances();
  });

  async function loadInstances() {
    instancesLoading = true;
    try {
      const result = await getKnownInstances();
      instances = result.data;
    } catch {
      addToast('Failed to load instances', 'error');
    } finally {
      instancesLoading = false;
    }
  }

  async function loadPolicies() {
    policiesLoading = true;
    try {
      policies = await getFederationPolicies();
    } catch {
      addToast('Failed to load policies', 'error');
    } finally {
      policiesLoading = false;
    }
  }

  async function loadDelivery() {
    deliveryLoading = true;
    try {
      deliveryStats = await getDeliveryQueueStats();
    } catch {
      addToast('Failed to load delivery stats', 'error');
    } finally {
      deliveryLoading = false;
    }
  }

  $effect(() => {
    if (activeTab === 'policies' && policies.length === 0 && !policiesLoading) {
      loadPolicies();
    } else if (activeTab === 'delivery' && !deliveryStats && !deliveryLoading) {
      loadDelivery();
    }
  });

  async function handleAddPolicy() {
    if (!newPolicyDomain.trim()) return;
    try {
      const policy = await createFederationPolicy({
        domain: newPolicyDomain,
        policy: newPolicyType,
        reason: newPolicyReason || null
      });
      policies = [...policies, policy];
      newPolicyDomain = '';
      newPolicyReason = '';
      addToast('Federation policy created', 'success');
    } catch {
      addToast('Failed to create policy', 'error');
    }
  }

  async function handleDeletePolicy(id: string) {
    try {
      await deleteFederationPolicy(id);
      policies = policies.filter((p) => p.id !== id);
      addToast('Policy removed', 'success');
    } catch {
      addToast('Failed to remove policy', 'error');
    }
  }

  async function handleRetryDelivery() {
    retrying = true;
    try {
      await retryDeliveryQueue();
      addToast('Delivery queue retry started', 'success');
      await loadDelivery();
    } catch {
      addToast('Failed to retry delivery queue', 'error');
    } finally {
      retrying = false;
    }
  }

  function formatDate(iso: string | null): string {
    if (!iso) return 'Never';
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }
</script>

<svelte:head>
  <title>Federation - Admin</title>
</svelte:head>

<div class="federation-page">
  <h1 class="page-title">Federation</h1>

  <Tabs {tabs} bind:active={activeTab}>
    {#if activeTab === 'instances'}
      <DataTable
        columns={instanceColumns}
        rows={instanceRows}
        bind:sortKey={instanceSortKey}
        bind:sortDir={instanceSortDir}
        loading={instancesLoading}
        emptyMessage="No known instances"
      >
        {#snippet rowContent(row)}
          <td><strong>{row['domain']}</strong></td>
          <td>
            {#if row['software']}
              {row['software']}
              {#if row['software_version']}
                <span class="text-secondary"> {row['software_version']}</span>
              {/if}
            {:else}
              <span class="text-tertiary">Unknown</span>
            {/if}
          </td>
          <td>{(row['user_count'] as number).toLocaleString()}</td>
          <td>{formatDate(row['last_activity_at'] as string | null)}</td>
          <td>
            <span class="instance-status instance-{row['status']}">
              {row['status']}
            </span>
          </td>
        {/snippet}
      </DataTable>

    {:else if activeTab === 'policies'}
      <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAddPolicy(); }}>
        <input class="input" type="text" bind:value={newPolicyDomain} placeholder="domain.example" required />
        <select class="input" bind:value={newPolicyType} style="width: 140px">
          <option value="allow">Allow</option>
          <option value="silence">Silence</option>
          <option value="suspend">Suspend</option>
        </select>
        <input class="input" type="text" bind:value={newPolicyReason} placeholder="Reason (optional)" />
        <button class="btn btn-primary" type="submit">Add Policy</button>
      </form>

      <div class="list-items">
        {#each policies as policy (policy.id)}
          <div class="list-item card">
            <div class="list-item-info">
              <strong>{policy.domain}</strong>
              <span class="policy-badge policy-{policy.policy}">{policy.policy}</span>
              {#if policy.reason}
                <span class="text-secondary">- {policy.reason}</span>
              {/if}
            </div>
            <button
              class="btn btn-sm btn-danger"
              type="button"
              onclick={() => handleDeletePolicy(policy.id)}
            >Remove</button>
          </div>
        {:else}
          <p class="empty-text">No federation policies configured</p>
        {/each}
      </div>

    {:else if activeTab === 'delivery'}
      {#if deliveryLoading}
        <div class="delivery-loading">
          <div class="skeleton" style="height: 80px"></div>
        </div>
      {:else if deliveryStats}
        <div class="delivery-grid">
          <div class="delivery-stat card">
            <div class="delivery-label">Pending</div>
            <div class="delivery-value">{deliveryStats.pending.toLocaleString()}</div>
          </div>
          <div class="delivery-stat card">
            <div class="delivery-label">Failed</div>
            <div class="delivery-value delivery-failed">{deliveryStats.failed.toLocaleString()}</div>
          </div>
          <div class="delivery-stat card">
            <div class="delivery-label">Retrying</div>
            <div class="delivery-value delivery-retrying">{deliveryStats.retrying.toLocaleString()}</div>
          </div>
        </div>
        <div class="delivery-actions">
          <button
            class="btn btn-primary"
            type="button"
            disabled={retrying}
            onclick={handleRetryDelivery}
          >
            {retrying ? 'Retrying...' : 'Retry Failed Deliveries'}
          </button>
          <button class="btn btn-outline" type="button" onclick={loadDelivery}>
            Refresh
          </button>
        </div>
      {/if}
    {/if}
  </Tabs>
</div>

<style>
  .federation-page {
    max-width: 1100px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .instance-status {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .instance-up {
    background: var(--color-success-soft);
    color: #166534;
  }

  .instance-down {
    background: var(--color-danger-soft);
    color: #991b1b;
  }

  .instance-unknown {
    background: var(--color-surface);
    color: var(--color-text-secondary);
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

  .policy-badge {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .policy-allow {
    background: var(--color-success-soft);
    color: #166534;
  }

  .policy-silence {
    background: var(--color-warning-soft);
    color: #92400e;
  }

  .policy-suspend {
    background: var(--color-danger-soft);
    color: #991b1b;
  }

  .delivery-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: var(--space-4);
    margin-block-end: var(--space-4);
  }

  .delivery-stat {
    text-align: center;
    padding: var(--space-6);
  }

  .delivery-label {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-2);
  }

  .delivery-value {
    font-size: var(--text-3xl);
    font-weight: 700;
  }

  .delivery-failed {
    color: var(--color-danger);
  }

  .delivery-retrying {
    color: var(--color-warning);
  }

  .delivery-actions {
    display: flex;
    gap: var(--space-3);
  }

  .delivery-loading {
    padding: var(--space-4) 0;
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }
</style>

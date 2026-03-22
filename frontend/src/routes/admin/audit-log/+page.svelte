<script lang="ts">
  import { onMount } from 'svelte';
  import DataTable from '$lib/components/admin/DataTable.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getAuditLog } from '$lib/api/admin.js';
  import type { AuditLogEntry } from '$lib/api/types.js';

  let entries: AuditLogEntry[] = $state([]);
  let loading = $state(true);
  let sortKey = $state('created_at');
  let sortDir = $state<'asc' | 'desc'>('desc');

  // Filters
  let actionFilter = $state('');
  let actorFilter = $state('');
  let dateFrom = $state('');
  let dateTo = $state('');

  const columns = [
    { key: 'actor', label: 'Actor' },
    { key: 'action', label: 'Action', sortable: true },
    { key: 'target_type', label: 'Target' },
    { key: 'created_at', label: 'Date', sortable: true },
    { key: 'details', label: 'Details' }
  ];

  let filteredEntries = $derived(
    entries.filter((e) => {
      if (actionFilter && !e.action.toLowerCase().includes(actionFilter.toLowerCase())) return false;
      if (actorFilter && !e.actor.handle.toLowerCase().includes(actorFilter.toLowerCase())) return false;
      if (dateFrom) {
        const from = new Date(dateFrom);
        if (new Date(e.created_at) < from) return false;
      }
      if (dateTo) {
        const to = new Date(dateTo);
        to.setDate(to.getDate() + 1);
        if (new Date(e.created_at) > to) return false;
      }
      return true;
    })
  );

  let tableRows = $derived(
    filteredEntries.map((e) => ({ ...e } as Record<string, unknown>))
  );

  onMount(async () => {
    try {
      const result = await getAuditLog();
      entries = result.data;
    } catch {
      addToast('Failed to load audit log', 'error');
    } finally {
      loading = false;
    }
  });

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  }

  function formatDetails(details: Record<string, unknown> | null): string {
    if (!details) return '-';
    return Object.entries(details)
      .map(([k, v]) => `${k}: ${v}`)
      .join(', ');
  }
</script>

<svelte:head>
  <title>Audit Log - Admin</title>
</svelte:head>

<div class="audit-page">
  <h1 class="page-title">Audit Log</h1>

  <div class="filters">
    <input
      type="text"
      class="input"
      placeholder="Filter by action..."
      bind:value={actionFilter}
    />
    <input
      type="text"
      class="input"
      placeholder="Filter by actor..."
      bind:value={actorFilter}
    />
    <input
      type="date"
      class="input date-input"
      bind:value={dateFrom}
      aria-label="From date"
    />
    <input
      type="date"
      class="input date-input"
      bind:value={dateTo}
      aria-label="To date"
    />
  </div>

  <DataTable
    {columns}
    rows={tableRows}
    bind:sortKey
    bind:sortDir
    {loading}
    emptyMessage="No audit log entries found"
  >
    {#snippet rowContent(row)}
      <td>
        <span class="actor-handle">@{(row['actor'] as Record<string, unknown>)?.['handle'] ?? 'system'}</span>
      </td>
      <td>
        <span class="action-label">{row['action']}</span>
      </td>
      <td>
        {#if row['target_type']}
          <span class="target-info">
            {row['target_type']}
            {#if row['target_id']}
              <span class="target-id">#{(row['target_id'] as string).slice(0, 8)}</span>
            {/if}
          </span>
        {:else}
          <span class="text-tertiary">-</span>
        {/if}
      </td>
      <td>{formatDate(row['created_at'] as string)}</td>
      <td>
        <span class="details-text" title={formatDetails(row['details'] as Record<string, unknown> | null)}>
          {formatDetails(row['details'] as Record<string, unknown> | null)}
        </span>
      </td>
    {/snippet}
  </DataTable>
</div>

<style>
  .audit-page {
    max-width: 1100px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .filters {
    display: flex;
    gap: var(--space-2);
    margin-block-end: var(--space-4);
    flex-wrap: wrap;
  }

  .filters .input {
    flex: 1;
    min-width: 150px;
  }

  .date-input {
    max-width: 160px;
  }

  .actor-handle {
    font-weight: 600;
    font-size: var(--text-sm);
  }

  .action-label {
    font-size: var(--text-sm);
    font-family: var(--font-mono);
    background: var(--color-surface);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
  }

  .target-info {
    font-size: var(--text-sm);
  }

  .target-id {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    margin-inline-start: var(--space-1);
  }

  .details-text {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    max-width: 200px;
    display: block;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  @media (max-width: 768px) {
    .filters {
      flex-direction: column;
    }

    .filters .input,
    .date-input {
      max-width: none;
    }
  }
</style>

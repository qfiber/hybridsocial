<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Column {
    key: string;
    label: string;
    sortable?: boolean;
    width?: string;
  }

  let {
    columns,
    rows,
    sortKey = $bindable(''),
    sortDir = $bindable('asc' as 'asc' | 'desc'),
    onrowclick,
    loading = false,
    emptyMessage = 'No data found',
    rowContent
  }: {
    columns: Column[];
    rows: Record<string, unknown>[];
    sortKey?: string;
    sortDir?: 'asc' | 'desc';
    onrowclick?: (row: Record<string, unknown>) => void;
    loading?: boolean;
    emptyMessage?: string;
    rowContent: Snippet<[Record<string, unknown>]>;
  } = $props();

  function handleSort(col: Column) {
    if (!col.sortable) return;
    if (sortKey === col.key) {
      sortDir = sortDir === 'asc' ? 'desc' : 'asc';
    } else {
      sortKey = col.key;
      sortDir = 'asc';
    }
  }

  function handleRowClick(row: Record<string, unknown>) {
    onrowclick?.(row);
  }

  function handleRowKeydown(e: KeyboardEvent, row: Record<string, unknown>) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onrowclick?.(row);
    }
  }
</script>

<div class="table-wrapper">
  <table class="data-table">
    <thead>
      <tr>
        {#each columns as col (col.key)}
          <th
            class:sortable={col.sortable}
            class:sorted={sortKey === col.key}
            style={col.width ? `width: ${col.width}` : ''}
          >
            {#if col.sortable}
              <button
                class="sort-btn"
                type="button"
                onclick={() => handleSort(col)}
                aria-label="Sort by {col.label}"
              >
                {col.label}
                {#if sortKey === col.key}
                  <span class="sort-indicator" aria-hidden="true">
                    {sortDir === 'asc' ? '\u2191' : '\u2193'}
                  </span>
                {/if}
              </button>
            {:else}
              {col.label}
            {/if}
          </th>
        {/each}
      </tr>
    </thead>
    <tbody>
      {#if loading}
        {#each Array(5) as _}
          <tr class="skeleton-row">
            {#each columns as _col}
              <td><div class="skeleton" style="height: 16px; width: 80%"></div></td>
            {/each}
          </tr>
        {/each}
      {:else if rows.length === 0}
        <tr>
          <td colspan={columns.length} class="empty-cell">
            {emptyMessage}
          </td>
        </tr>
      {:else}
        {#each rows as row (row['id'] ?? rows.indexOf(row))}
          <tr
            class:clickable={!!onrowclick}
            onclick={() => handleRowClick(row)}
            onkeydown={(e) => handleRowKeydown(e, row)}
            role={onrowclick ? 'button' : undefined}
            tabindex={onrowclick ? 0 : undefined}
          >
            {@render rowContent(row)}
          </tr>
        {/each}
      {/if}
    </tbody>
  </table>
</div>

<style>
  .table-wrapper {
    overflow-x: auto;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
  }

  .data-table {
    width: 100%;
    border-collapse: collapse;
    font-size: var(--text-sm);
  }

  .data-table th {
    text-align: start;
    padding: var(--space-3) var(--space-4);
    background: var(--color-surface);
    color: var(--color-text-secondary);
    font-weight: 600;
    font-size: var(--text-xs);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    border-block-end: 1px solid var(--color-border);
    white-space: nowrap;
  }

  .data-table td {
    padding: var(--space-4) var(--space-4);
    border-block-end: 1px solid var(--color-border);
    color: var(--color-text);
    vertical-align: middle;
  }

  .data-table tbody tr:nth-child(even) {
    background: var(--color-surface, #f9fafb);
  }

  .data-table tbody tr:hover {
    background: var(--color-surface-container-low, #f0f2f3);
  }

  .data-table tbody tr:last-child td {
    border-block-end: none;
  }

  .data-table tbody tr.clickable {
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .data-table tbody tr.clickable:hover {
    background: var(--color-surface);
  }

  .sort-btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    background: none;
    border: none;
    font: inherit;
    font-weight: 600;
    font-size: var(--text-xs);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: inherit;
    cursor: pointer;
    padding: 0;
  }

  .sort-btn:hover {
    color: var(--color-text);
  }

  .sort-indicator {
    font-size: var(--text-sm);
  }

  .empty-cell {
    text-align: center;
    color: var(--color-text-tertiary);
    padding: var(--space-8) var(--space-4);
  }

  .skeleton-row td {
    padding: var(--space-3) var(--space-4);
  }
</style>

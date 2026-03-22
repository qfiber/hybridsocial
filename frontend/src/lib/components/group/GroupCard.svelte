<script lang="ts">
  import type { Group } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';

  let {
    group,
    onclick
  }: {
    group: Group;
    onclick?: () => void;
  } = $props();

  let descSnippet = $derived(
    group.description
      ? group.description.length > 100
        ? group.description.slice(0, 100) + '...'
        : group.description
      : ''
  );

  let memberLabel = $derived(
    group.member_count === 1 ? '1 member' : `${group.member_count.toLocaleString()} members`
  );
</script>

<button type="button" class="group-card" onclick={onclick}>
  <Avatar src={group.avatar_url} name={group.name} size="lg" />
  <div class="group-info">
    <div class="group-name-row">
      <span class="group-name">{group.name}</span>
      {#if group.visibility === 'private'}
        <svg class="lock-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-label="Private group">
          <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
          <path d="M7 11V7a5 5 0 0110 0v4" />
        </svg>
      {/if}
    </div>
    <span class="group-members">{memberLabel}</span>
    {#if descSnippet}
      <p class="group-description">{descSnippet}</p>
    {/if}
  </div>
</button>

<style>
  .group-card {
    display: flex;
    gap: var(--space-3);
    padding: var(--space-4);
    border-radius: var(--radius-lg);
    background: var(--color-surface);
    transition: box-shadow var(--transition-fast);
    border: none;
    width: 100%;
    text-align: start;
    cursor: pointer;
  }

  .group-card:hover {
    box-shadow: var(--shadow-md);
  }

  .group-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .group-name-row {
    display: flex;
    align-items: center;
    gap: var(--space-1);
  }

  .group-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .lock-icon {
    color: var(--color-text-tertiary);
    flex-shrink: 0;
  }

  .group-members {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .group-description {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    line-height: 1.4;
    margin-block-start: var(--space-1);
  }
</style>

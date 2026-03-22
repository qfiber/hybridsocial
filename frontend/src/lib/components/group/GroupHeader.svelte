<script lang="ts">
  import type { GroupDetail } from '$lib/api/groups.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';

  let {
    group,
    onjoin,
    onleave,
    onsettings
  }: {
    group: GroupDetail;
    onjoin?: () => void;
    onleave?: () => void;
    onsettings?: () => void;
  } = $props();

  let memberLabel = $derived(
    group.member_count === 1 ? '1 member' : `${group.member_count.toLocaleString()} members`
  );

  let actionLabel = $derived(
    group.is_member
      ? 'Leave'
      : group.pending_request
        ? 'Pending'
        : 'Join'
  );

  let isAdmin = $derived(group.role === 'owner' || group.role === 'admin');

  function handleAction() {
    if (group.is_member) {
      onleave?.();
    } else if (!group.pending_request) {
      onjoin?.();
    }
  }
</script>

<div class="group-header">
  {#if group.header_url}
    <div class="cover-image">
      <img src={group.header_url} alt="" class="cover-img" />
    </div>
  {:else}
    <div class="cover-placeholder"></div>
  {/if}

  <div class="header-body">
    <div class="avatar-row">
      <Avatar src={group.avatar_url} name={group.name} size="xl" />
    </div>

    <div class="header-info">
      <div class="header-title-row">
        <div class="header-titles">
          <h1 class="group-title">{group.name}</h1>
          <div class="group-meta">
            <span class="group-visibility">{group.visibility}</span>
            <span class="group-member-count">{memberLabel}</span>
          </div>
        </div>
        <div class="header-actions">
          {#if isAdmin}
            <button type="button" class="btn btn-ghost" onclick={onsettings} aria-label="Group settings">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="3" />
                <path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z" />
              </svg>
            </button>
          {/if}
          <button
            type="button"
            class="btn"
            class:btn-primary={!group.is_member && !group.pending_request}
            class:btn-outline={group.is_member || group.pending_request}
            onclick={handleAction}
            disabled={group.pending_request}
          >
            {actionLabel}
          </button>
        </div>
      </div>

      {#if group.description}
        <p class="group-description">{group.description}</p>
      {/if}
    </div>
  </div>
</div>

<style>
  .group-header {
    background: var(--color-surface-raised);
    border-radius: var(--radius-lg);
    overflow: hidden;
    border: 1px solid var(--color-border);
  }

  .cover-image {
    height: 160px;
    overflow: hidden;
  }

  .cover-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .cover-placeholder {
    height: 100px;
    background: linear-gradient(var(--gradient-direction), var(--gradient-start), var(--gradient-end));
  }

  .header-body {
    padding: 0 var(--space-6) var(--space-6);
  }

  .avatar-row {
    margin-block-start: -32px;
    margin-block-end: var(--space-3);
  }

  .avatar-row :global(.avatar) {
    border: 3px solid var(--color-surface-raised);
  }

  .header-info {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .header-title-row {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-4);
    flex-wrap: wrap;
  }

  .header-titles {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .group-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    line-height: 1.3;
  }

  .group-meta {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .group-visibility {
    text-transform: capitalize;
  }

  .group-visibility::after {
    content: '\00b7';
    margin-inline-start: var(--space-2);
  }

  .header-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .group-description {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.5;
  }
</style>

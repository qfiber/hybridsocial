<script lang="ts">
  let {
    type,
    label,
    size = 'sm'
  }: {
    type: 'owner' | 'admin' | 'moderator' | 'editor' | 'bot' | 'verified_l1' | 'verified_l2' | 'verified_l3';
    label?: string;
    size?: 'sm' | 'md';
  } = $props();

  const icons: Record<string, string> = {
    owner: 'M12 2l2.09 6.26L21 9.27l-5.46 4.73L17.18 21 12 17.27 6.82 21l1.64-6.97L3 9.27l6.91-1.01L12 2z',
    admin: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z',
    moderator: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z M9 12l2 2 4-4',
    editor: 'M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7 M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z',
    bot: 'M12 2a2 2 0 012 2c0 .74-.4 1.39-1 1.73V7h1a7 7 0 017 7v1H3v-1a7 7 0 017-7h1V5.73c-.6-.34-1-.99-1-1.73a2 2 0 012-2z M7.5 13a1.5 1.5 0 100 3 1.5 1.5 0 000-3z M16.5 13a1.5 1.5 0 100 3 1.5 1.5 0 000-3z',
    verified_l1: 'M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z',
    verified_l2: 'M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z',
    verified_l3: 'M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z'
  };

  const defaultLabels: Record<string, string> = {
    owner: 'Owner',
    admin: 'Admin',
    moderator: 'Mod',
    editor: 'Editor',
    bot: 'Bot',
    verified_l1: 'Verified',
    verified_l2: 'Verified',
    verified_l3: 'Verified Pro'
  };

  let displayLabel = $derived(label || defaultLabels[type] || type);
</script>

<span class="role-badge badge-{type} badge-{size}" title={displayLabel}>
  <svg class="badge-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <path d={icons[type] || icons.admin} />
  </svg>
  {#if size === 'md'}
    <span class="badge-label">{displayLabel}</span>
  {/if}
</span>

<style>
  .role-badge {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    border-radius: var(--radius-full);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    flex-shrink: 0;
    vertical-align: middle;
  }

  .badge-sm {
    padding: 1px 5px;
    font-size: 0.55rem;
  }

  .badge-sm .badge-icon {
    width: 10px;
    height: 10px;
  }

  .badge-md {
    padding: 2px 8px;
    font-size: 0.65rem;
  }

  .badge-md .badge-icon {
    width: 12px;
    height: 12px;
  }

  .badge-icon {
    flex-shrink: 0;
  }

  /* Colors by role */
  .badge-owner {
    background: #fef3c7;
    color: #92400e;
  }

  .badge-owner .badge-icon {
    stroke: #d97706;
  }

  .badge-admin {
    background: var(--color-primary-soft);
    color: var(--color-primary);
  }

  .badge-admin .badge-icon {
    stroke: var(--color-primary);
  }

  .badge-moderator {
    background: #e0e7ff;
    color: #4338ca;
  }

  .badge-moderator .badge-icon {
    stroke: #6366f1;
  }

  .badge-editor {
    background: #fce7f3;
    color: #9d174d;
  }

  .badge-editor .badge-icon {
    stroke: #ec4899;
  }

  .badge-bot {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .badge-bot .badge-icon {
    stroke: var(--color-text-secondary);
  }

  /* Verification tiers */
  .badge-verified_l1 {
    background: #e0f2fe;
    color: #0369a1;
  }

  .badge-verified_l1 .badge-icon {
    stroke: #0ea5e9;
  }

  .badge-verified_l2 {
    background: #ede9fe;
    color: #6d28d9;
  }

  .badge-verified_l2 .badge-icon {
    stroke: #8b5cf6;
  }

  .badge-verified_l3 {
    background: linear-gradient(135deg, #fef3c7, #fde68a);
    color: #92400e;
  }

  .badge-verified_l3 .badge-icon {
    stroke: #d97706;
  }
</style>

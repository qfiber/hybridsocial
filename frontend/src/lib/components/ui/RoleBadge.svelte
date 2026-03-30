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

  const badgeImages: Record<string, string> = {
    owner: '/badges/OwnerBadg.svg',
    admin: '/badges/AdminBadge.svg',
    moderator: '/badges/ModeratorBadge.svg',
    bot: '/badges/RobotBadge.svg',
    verified_l1: '/badges/InitBadge.svg',
    verified_l2: '/badges/ProBadge.svg',
    verified_l3: '/badges/MaxBadge.svg',
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
  let imgSrc = $derived(badgeImages[type]);
  let imgSize = $derived(size === 'sm' ? 14 : 18);
</script>

{#if imgSrc}
  <span class="role-badge badge-{size}" title={displayLabel}>
    <img src={imgSrc} alt={displayLabel} class="badge-img" width={imgSize} height={imgSize} />
  </span>
{:else}
  <span class="role-badge badge-fallback badge-{type} badge-{size}" title={displayLabel}>
    <span class="badge-dot"></span>
  </span>
{/if}

<style>
  .role-badge {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    flex-shrink: 0;
    vertical-align: middle;
  }

  .badge-img {
    display: block;
    flex-shrink: 0;
  }

  .badge-sm {
    font-size: 0.55rem;
  }

  .badge-md {
    font-size: 0.65rem;
  }

  .badge-label {
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    color: var(--color-text-secondary);
  }

  /* Fallback pill for types without custom SVG */
  .badge-fallback {
    padding: 1px 5px;
    border-radius: var(--radius-full);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .badge-fallback .badge-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
  }

  .badge-editor {
    background: #fce7f3;
    color: #9d174d;
  }

  .badge-bot {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }
</style>

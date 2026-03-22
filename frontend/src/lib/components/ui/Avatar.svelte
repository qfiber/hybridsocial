<script lang="ts">
  let {
    src = '',
    name = '',
    size = 'md'
  }: {
    src?: string | null;
    name?: string;
    size?: 'sm' | 'md' | 'lg' | 'xl';
  } = $props();

  let initials = $derived(
    name
      .split(' ')
      .slice(0, 2)
      .map((s) => s.charAt(0))
      .join('')
      .toUpperCase()
  );

  let imgError = $state(false);
  let showImage = $derived(!!src && !imgError);
</script>

<div class="avatar avatar-{size}" aria-label={name ? `Avatar for ${name}` : 'Avatar'}>
  {#if showImage}
    <img {src} alt={name || 'Avatar'} class="avatar-img" onerror={() => (imgError = true)} />
  {:else}
    <span class="avatar-initials">{initials || '?'}</span>
  {/if}
</div>

<style>
  .avatar {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--radius-full);
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-weight: 600;
    overflow: hidden;
    flex-shrink: 0;
  }

  .avatar-sm {
    width: 28px;
    height: 28px;
    font-size: var(--text-xs);
  }

  .avatar-md {
    width: 40px;
    height: 40px;
    font-size: var(--text-sm);
  }

  .avatar-lg {
    width: 56px;
    height: 56px;
    font-size: var(--text-lg);
  }

  .avatar-xl {
    width: 80px;
    height: 80px;
    font-size: var(--text-2xl);
  }

  .avatar-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .avatar-initials {
    line-height: 1;
    user-select: none;
  }
</style>

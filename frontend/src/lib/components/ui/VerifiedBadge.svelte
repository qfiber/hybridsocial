<script lang="ts">
  let {
    size = 'sm',
  }: {
    size?: 'sm' | 'md';
  } = $props();

  let iconSize = $derived(size === 'sm' ? 14 : 18);
</script>

<span class="verified-badge verified-{size}" title="Verified" aria-label="Verified account">
  <svg
    width={iconSize}
    height={iconSize}
    viewBox="0 0 24 24"
    fill="var(--color-primary)"
    aria-hidden="true"
  >
    <circle cx="12" cy="12" r="12" fill="var(--color-primary)" />
    <path
      d="M9.5 16.5L5 12l1.41-1.41L9.5 13.67l8.09-8.09L19 7l-9.5 9.5z"
      fill="white"
      stroke="none"
    />
  </svg>
</span>

<style>
  .verified-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    vertical-align: middle;
    line-height: 1;
  }

  .verified-sm {
    width: 14px;
    height: 14px;
  }

  .verified-md {
    width: 18px;
    height: 18px;
  }
</style>

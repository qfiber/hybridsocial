<script lang="ts">
  let {
    width = '100%',
    height = '16px',
    rounded = false
  }: {
    width?: string;
    height?: string;
    rounded?: boolean;
  } = $props();
</script>

<div
  class="skeleton-el"
  class:rounded
  style="width: {width}; height: {height}"
  aria-hidden="true"
></div>

<style>
  .skeleton-el {
    background: var(--color-border);
    border-radius: var(--radius-sm);
    animation: skeleton-pulse 1.5s ease-in-out infinite;
  }

  .skeleton-el.rounded {
    border-radius: var(--radius-full);
  }

  @keyframes skeleton-pulse {
    0%,
    100% {
      opacity: 0.4;
    }
    50% {
      opacity: 0.7;
    }
  }
</style>

<script lang="ts">
  let {
    size = 24,
    color = 'var(--color-primary)'
  }: {
    size?: number;
    color?: string;
  } = $props();
</script>

<svg
  class="spinner"
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill="none"
  style="--spinner-color: {color}"
  aria-label="Loading"
  role="status"
>
  <circle class="spinner-track" cx="12" cy="12" r="10" stroke-width="3" />
  <circle class="spinner-head" cx="12" cy="12" r="10" stroke-width="3" stroke-linecap="round" />
</svg>

<style>
  .spinner {
    animation: spin 0.8s linear infinite;
  }

  .spinner-track {
    stroke: var(--spinner-color);
    opacity: 0.2;
  }

  .spinner-head {
    stroke: var(--spinner-color);
    stroke-dasharray: 45 65;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>

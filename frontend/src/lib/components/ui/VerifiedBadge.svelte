<script lang="ts">
  let {
    size = 'sm',
  }: {
    size?: 'sm' | 'md';
  } = $props();

  let imgSize = $derived(size === 'sm' ? 14 : 18);
</script>

<span class="verified-badge verified-{size}" title="Verified" aria-label="Verified account">
  <img src="/badges/BasicBadge.svg" alt="Verified" width={imgSize} height={imgSize} class="verified-img" />
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

  .verified-img {
    display: block;
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

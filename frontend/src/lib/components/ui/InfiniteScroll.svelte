<script lang="ts">
  let {
    onLoadMore,
    loading = false,
    hasMore = true,
    threshold = 200
  }: {
    onLoadMore: () => void;
    loading?: boolean;
    hasMore?: boolean;
    threshold?: number;
  } = $props();

  let sentinelEl: HTMLDivElement | undefined = $state();

  $effect(() => {
    if (!sentinelEl || !hasMore) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && !loading && hasMore) {
          onLoadMore();
        }
      },
      { rootMargin: `${threshold}px` }
    );

    observer.observe(sentinelEl);

    return () => observer.disconnect();
  });
</script>

{#if hasMore}
  <div class="infinite-scroll-sentinel" bind:this={sentinelEl} aria-hidden="true"></div>
{/if}

<style>
  .infinite-scroll-sentinel {
    height: 1px;
    width: 100%;
  }
</style>

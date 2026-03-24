<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import { onMount } from 'svelte';

  let tag = $derived(page.params.tag);

  onMount(() => {
    goto(`/explore?q=%23${encodeURIComponent(tag)}`, { replaceState: true });
  });
</script>

<div style="padding: 2rem; text-align: center; color: var(--color-text-secondary);">
  Redirecting to #{tag}...
</div>

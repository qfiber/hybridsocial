<script lang="ts">
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import { get } from 'svelte/store';
  import { authStore } from '$lib/stores/auth.js';
  import { onMount } from 'svelte';

  onMount(() => {
    const state = get(authStore);
    if (state.user) {
      goto('/home', { replaceState: true });
    } else {
      goto('/login', { replaceState: true });
    }
  });
</script>

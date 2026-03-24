<script lang="ts">
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import { get } from 'svelte/store';
  import AppLayout from '$lib/components/layout/AppLayout.svelte';
  import { authStore, isLoggedIn } from '$lib/stores/auth.js';
  import { connectNotificationStream, disconnectNotificationStream } from '$lib/stores/notifications.js';
  import { cookieConsent, hasConsented } from '$lib/stores/consent.js';
  import CookieBanner from '$lib/components/ui/CookieBanner.svelte';
  import { api } from '$lib/api/client.js';
  import { subscribeToPush } from '$lib/utils/push.js';
  import { onMount } from 'svelte';

  let { children } = $props();
  let loggedIn = $state(false);
  let consented = $state(hasConsented());

  cookieConsent.subscribe((v) => (consented = v));
  const unsub = isLoggedIn.subscribe((v) => (loggedIn = v));

  onMount(() => {
    const state = get(authStore);

    // Redirect to login if not authenticated
    if (!state.user && state.initialized) {
      goto('/login');
      return;
    }

    // Connect notification SSE stream
    const token = api.getAccessToken();
    if (token) {
      const apiBase = import.meta.env.VITE_API_URL || 'http://localhost:4000';
      connectNotificationStream(apiBase, token);

      // Subscribe to web push notifications
      subscribeToPush(token);
    }

    return () => {
      disconnectNotificationStream();
      unsub();
    };
  });

  // Watch for logout while on authenticated pages
  $effect(() => {
    if (browser && !loggedIn) {
      const state = get(authStore);
      if (state.initialized) {
        goto('/login');
      }
    }
  });
</script>

{#if !consented}
  <CookieBanner onaccept={() => consented = true} />
{:else}
  <AppLayout>
    {@render children()}
  </AppLayout>
{/if}

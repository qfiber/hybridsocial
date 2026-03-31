<script lang="ts">
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import { get } from 'svelte/store';
  import AppLayout from '$lib/components/layout/AppLayout.svelte';
  import ConnectionBanner from '$lib/components/ui/ConnectionBanner.svelte';
  import OnboardingModal from '$lib/components/ui/OnboardingModal.svelte';
  import { authStore, isLoggedIn } from '$lib/stores/auth.js';
  import { connectNotificationStream, disconnectNotificationStream } from '$lib/stores/notifications.js';
  import { cookieConsent, hasConsented } from '$lib/stores/consent.js';
  import CookieBanner from '$lib/components/ui/CookieBanner.svelte';
  import { subscribeToPush } from '$lib/utils/push.js';
  import { loadFilters } from '$lib/stores/content-filters.js';
  import PostComposer from '$lib/components/post/PostComposer.svelte';
  import { onMount } from 'svelte';

  let { children } = $props();
  let loggedIn = $state(false);
  let consented = $state(hasConsented());
  let showOnboarding = $state(false);

  cookieConsent.subscribe((v) => (consented = v));
  const unsub = isLoggedIn.subscribe((v) => (loggedIn = v));

  onMount(() => {
    const state = get(authStore);

    // Redirect to login if not authenticated
    if (!state.user && state.initialized) {
      goto('/login');
      return;
    }

    // Connect notification SSE stream + push notifications (auth via httpOnly cookies)
    const apiBase = import.meta.env.VITE_API_URL || '';
    connectNotificationStream(apiBase);
    subscribeToPush();
    loadFilters();

    // Show onboarding for new users (no display_name set yet)
    const authState = get(authStore);
    if (authState.user && !authState.user.display_name && !localStorage.getItem('hs_onboarded')) {
      showOnboarding = true;
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
  <ConnectionBanner />
  <AppLayout>
    {@render children()}
  </AppLayout>
  <PostComposer />
  {#if showOnboarding}
    <OnboardingModal onclose={() => { showOnboarding = false; localStorage.setItem('hs_onboarded', '1'); }} />
  {/if}
{/if}

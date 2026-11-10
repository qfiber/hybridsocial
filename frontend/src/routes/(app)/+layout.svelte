<script lang="ts">
  import PublicLayout from '$lib/components/layout/PublicLayout.svelte';
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import AppLayout from '$lib/components/layout/AppLayout.svelte';
  import ConnectionBanner from '$lib/components/ui/ConnectionBanner.svelte';
  import StaffOtpBanner from '$lib/components/ui/StaffOtpBanner.svelte';
  import OnboardingModal from '$lib/components/ui/OnboardingModal.svelte';
  import { authStore } from '$lib/stores/auth.js';
  import { connectNotificationStream, disconnectNotificationStream, hydrateUnreadCount } from '$lib/stores/notifications.js';
  import { connectChatStream, disconnectChatStream } from '$lib/stores/chat-stream.js';
  import { initSound } from '$lib/stores/sound.js';
  import { initDmUnread } from '$lib/stores/dm-unread.js';
  import { cookieConsent, hasConsented } from '$lib/stores/consent.js';
  import CookieBanner from '$lib/components/ui/CookieBanner.svelte';
  import { syncPushSubscription } from '$lib/utils/push.js';
  import { loadFilters } from '$lib/stores/content-filters.js';
  import PostComposer from '$lib/components/post/PostComposer.svelte';
  import SudoModal from '$lib/components/admin/SudoModal.svelte';
  import KeyboardShortcutsModal from '$lib/components/ui/KeyboardShortcutsModal.svelte';
  import { installShortcuts } from '$lib/utils/shortcuts.js';
  import { onDestroy } from 'svelte';
  import { page } from '$app/state';

  // The floating "+" FAB was retired in favour of an inline "New
  // post" button at the foot of the left sidebar — see Sidebar.svelte.
  // PostComposer still needs to be mounted globally so the
  // `open-composer` event from anywhere (sidebar button, DM→post
  // fallback, group/page composer triggers) opens the modal.
  const showComposer = false;

  let { children } = $props();

  let authState = $state({ user: null as any, initialized: false });
  let consented = $state(hasConsented());
  let showOnboarding = $state(false);
  let streamsStarted = false;
  let redirecting = $state(false);

  cookieConsent.subscribe((v) => (consented = v));
  const unsubAuth = authStore.subscribe((s) => (authState = s));

  // A route's server load sets `publicView` when this page may be shown without
  // logging in. If a session cookie exists, hold for auth as usual so a logged-in
  // visitor doesn't get a flash of the logged-out layout.
  let publicView = $derived(page.data.publicView === true);
  let showPublic = $derived(
    publicView && !authState.user && (authState.initialized || !page.data.hasSession),
  );

  // Gate rendering + side-effects on auth being resolved. Until the
  // root layout's initAuth() finishes we don't know whether the user
  // is logged in, so rendering the authed app shell (or connecting
  // SSE streams) just produces 401s and a misleading "Connection
  // lost" banner before the login redirect fires.
  $effect(() => {
    if (!browser || !authState.initialized) return;

    if (!authState.user) {
      if (publicView) return;
      if (!redirecting) {
        redirecting = true;
        goto('/login');
      }
      return;
    }

    if (!streamsStarted) {
      streamsStarted = true;
      const apiBase = import.meta.env.VITE_API_URL || '';
      connectNotificationStream(apiBase);
      hydrateUnreadCount();
      connectChatStream(apiBase);
      initSound();
      initDmUnread();
      syncPushSubscription();
      loadFilters();
      uninstallShortcuts = installShortcuts();

      if (!authState.user.onboarded_at) {
        showOnboarding = true;
      }
    }
  });

  let uninstallShortcuts: (() => void) | null = null;

  onDestroy(() => {
    disconnectNotificationStream();
    disconnectChatStream();
    unsubAuth();
    uninstallShortcuts?.();
  });
</script>

{#if showPublic}
  <!-- No session means no cookies yet, so the consent wall isn't needed here, and
       it would hide the page from visitors and search engines. -->
  <PublicLayout>
    {@render children()}
  </PublicLayout>
{:else if !consented}
  <CookieBanner onaccept={() => consented = true} />
{:else if !authState.initialized || !authState.user}
  <!-- Hold the shell blank until auth is resolved. Rendering authed
       pages before we know the user's status fires off 401s and a
       spurious "Connection lost" banner right before the redirect
       to /login. -->
{:else}
  <ConnectionBanner />
  <!-- Reminds staff who haven't enabled 2FA that the admin panel is
       locked behind it. Self-hides once 2FA is on or for non-staff
       accounts; dismissible per session. -->
  <StaffOtpBanner />
  <AppLayout>
    {@render children()}
  </AppLayout>
  <!-- Always mounted so the DM→direct-post fallback can dispatch
       an open-composer event from /messages/new (where the FAB is
       hidden). The FAB itself stays hidden on messages/admin/settings. -->
  <PostComposer showFab={showComposer} />
  <!-- Global step-up challenge: any admin-gated call outside /admin
       (moderation panel on profiles, etc.) that 403s with
       auth.sudo_required lands here so the user can unlock without
       detouring through the admin dashboard. -->
  <SudoModal />
  <!-- `?` cheat sheet for the global keyboard shortcuts. -->
  <KeyboardShortcutsModal />
  {#if showOnboarding}
    <OnboardingModal onclose={() => { showOnboarding = false; }} />
  {/if}
{/if}

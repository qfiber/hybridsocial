<script lang="ts">
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import { get } from 'svelte/store';
  import { onMount } from 'svelte';
  import { authStore, currentUser, isStaff, initAuth } from '$lib/stores/auth.js';
  import { addToast } from '$lib/stores/toast.js';
  import AdminSidebar from '$lib/components/admin/AdminSidebar.svelte';
  import Toast from '$lib/components/ui/Toast.svelte';

  let { children } = $props();
  let authorized = $state(false);
  let checking = $state(true);

  onMount(async () => {
    // Ensure auth is fully initialized (handles page refresh with cookie-based session)
    let state = get(authStore);
    if (!state.initialized) {
      await initAuth();
      state = get(authStore);
    }

    // Not logged in
    if (!state.user) {
      goto('/login', { replaceState: true });
      return;
    }

    // Not staff — don't reveal that admin exists
    if (!isStaff() && !state.user.is_admin) {
      goto('/home', { replaceState: true });
      return;
    }

    authorized = true;
    checking = false;
  });

  // Watch for logout or role changes while on admin pages
  $effect(() => {
    if (!browser || checking) return;

    const state = get(authStore);
    if (state.initialized && !state.user) {
      goto('/login', { replaceState: true });
    }
  });
</script>

{#if authorized}
  <div class="admin-layout">
    <AdminSidebar />
    <main class="admin-content">
      {@render children()}
    </main>
  </div>
  <Toast />
{:else}
  <div class="admin-loading">
    <div class="admin-loading-spinner"></div>
  </div>
{/if}

<style>
  .admin-layout {
    display: flex;
    min-height: 100vh;
  }

  .admin-content {
    flex: 1;
    min-width: 0;
    padding: var(--space-6) var(--space-8);
    background: var(--color-bg);
    overflow-y: auto;
  }

  .admin-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
  }

  .admin-loading-spinner {
    width: 32px;
    height: 32px;
    border: 3px solid var(--color-border);
    border-top-color: var(--color-primary);
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  @media (max-width: 1024px) {
    .admin-content {
      padding: var(--space-4);
    }
  }
</style>

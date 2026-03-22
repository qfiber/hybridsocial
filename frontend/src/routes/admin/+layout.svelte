<script lang="ts">
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import { get } from 'svelte/store';
  import { onMount } from 'svelte';
  import { authStore, currentUser, isStaff } from '$lib/stores/auth.js';
  import { addToast } from '$lib/stores/toast.js';
  import AdminSidebar from '$lib/components/admin/AdminSidebar.svelte';
  import Toast from '$lib/components/ui/Toast.svelte';
  import type { Identity } from '$lib/api/types.js';

  let { children } = $props();
  let authorized = $state(false);
  let user: Identity | null = $state(null);

  currentUser.subscribe((v) => (user = v));

  onMount(() => {
    const state = get(authStore);

    if (!state.user || !state.initialized) {
      goto('/login');
      return;
    }

    if (!isStaff()) {
      addToast('You do not have admin access', 'error');
      goto('/home');
      return;
    }

    if (!state.user.two_factor_enabled) {
      addToast('2FA required for admin access', 'info');
      goto('/settings/security');
      return;
    }

    authorized = true;
  });

  $effect(() => {
    if (browser && user !== null && !isStaff()) {
      addToast('You do not have admin access', 'error');
      goto('/home');
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

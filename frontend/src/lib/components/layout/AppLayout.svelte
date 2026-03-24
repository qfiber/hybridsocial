<script lang="ts">
  import type { Snippet } from 'svelte';
  import { page } from '$app/state';
  import Header from './Header.svelte';
  import Sidebar from './Sidebar.svelte';
  import RightSidebar from './RightSidebar.svelte';
  import BottomTabs from './BottomTabs.svelte';
  import AnnouncementBanner from './AnnouncementBanner.svelte';
  import AppBanner from './AppBanner.svelte';
  import Toast from '$lib/components/ui/Toast.svelte';

  let {
    children
  }: {
    children: Snippet;
  } = $props();

  const hideRightSidebarPaths = ['/settings', '/messages', '/admin'];
  const fullWidthPaths = ['/messages', '/admin', '/settings'];

  let showRightSidebar = $derived(
    !hideRightSidebarPaths.some(p => page.url.pathname.startsWith(p))
  );

  let isFullWidth = $derived(
    fullWidthPaths.some(p => page.url.pathname.startsWith(p))
  );
</script>

<Header />
<div class="app-layout" class:no-right-sidebar={!showRightSidebar}>
  <Sidebar />
  <main class="feed-column" class:full-width={isFullWidth}>
    <AppBanner />
    <AnnouncementBanner />
    {@render children()}
  </main>
  {#if showRightSidebar}
    <RightSidebar />
  {/if}
</div>
<BottomTabs />
<Toast />

<style>
  .app-layout {
    display: grid;
    grid-template-columns: var(--sidebar-width) minmax(0, 1fr) var(--right-sidebar-width);
    max-width: 1200px;
    margin: 0 auto;
    padding-top: var(--header-height);
    min-height: 100vh;
  }

  .app-layout.no-right-sidebar {
    grid-template-columns: var(--sidebar-width) minmax(0, 1fr);
  }

  .feed-column {
    max-width: var(--feed-max-width);
    width: 100%;
    margin: 0 auto;
    padding: var(--space-4);
  }

  .feed-column.full-width {
    max-width: none;
    padding: 0;
  }

  /* Tablet: icon-only sidebar, no right sidebar */
  @media (max-width: 1200px) {
    .app-layout {
      grid-template-columns: 64px minmax(0, 1fr);
    }
  }

  /* Mobile: no sidebars, bottom tabs */
  @media (max-width: 768px) {
    .app-layout {
      grid-template-columns: 1fr;
    }

    .feed-column {
      padding: var(--space-2);
      padding-block-end: calc(var(--header-height) + var(--space-2));
    }
  }
</style>

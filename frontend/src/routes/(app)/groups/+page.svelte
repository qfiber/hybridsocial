<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import type { Group } from '$lib/api/types.js';
  import { getGroups, searchGroups } from '$lib/api/groups.js';
  import GroupCard from '$lib/components/group/GroupCard.svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let activeTab = $state('my-groups');
  let myGroups = $state<Group[]>([]);
  let discoverGroups = $state<Group[]>([]);
  let loading = $state(true);
  let discoverLoading = $state(false);
  let discoverLoaded = $state(false);
  let searchQuery = $state('');
  let searchTimeout: ReturnType<typeof setTimeout> | undefined;
  let myCursor = $state<string | null>(null);
  let discoverCursor = $state<string | null>(null);
  let hasMoreMy = $state(true);
  let hasMoreDiscover = $state(true);

  const tabs = [
    { id: 'my-groups', label: 'My Groups' },
    { id: 'discover', label: 'Discover' }
  ];

  onMount(async () => {
    try {
      const result = await getGroups('member');
      myGroups = Array.isArray(result) ? result : (result as any).data || [];
      hasMoreMy = myGroups.length >= 20;
    } catch {
      // Error loading groups
    } finally {
      loading = false;
    }
  });

  $effect(() => {
    if (activeTab === 'discover' && !discoverLoaded && !discoverLoading) {
      loadDiscover();
    }
  });

  async function loadDiscover() {
    discoverLoading = true;
    try {
      const result = await getGroups('discover');
      discoverGroups = Array.isArray(result) ? result : (result as any).data || [];
      hasMoreDiscover = discoverGroups.length >= 20;
    } catch {
      // Error loading discover
    } finally {
      discoverLoading = false;
      discoverLoaded = true;
    }
  }

  function handleSearch() {
    if (searchTimeout) clearTimeout(searchTimeout);
    const q = searchQuery.trim();
    if (q.length < 2) {
      if (discoverGroups.length === 0) loadDiscover();
      return;
    }
    discoverLoading = true;
    searchTimeout = setTimeout(async () => {
      try {
        const result = await searchGroups(q);
        discoverGroups = result.data;
        discoverCursor = result.next_cursor;
        hasMoreDiscover = !!result.next_cursor;
      } catch {
        // Error searching
      } finally {
        discoverLoading = false;
      }
    }, 300);
  }

  function openGroup(id: string) {
    goto(`/groups/${id}`);
  }
</script>

<svelte:head>
  <title>Groups - HybridSocial</title>
</svelte:head>

<div class="groups-page">
  <div class="page-header">
    <h1 class="page-title">Groups</h1>
  </div>

  <Tabs {tabs} bind:active={activeTab}>
    {#if activeTab === 'my-groups'}
      {#if loading}
        <div class="tab-loading">
          <Spinner />
        </div>
      {:else if myGroups.length === 0}
        <div class="tab-empty">
          <p class="empty-text">You have not joined any groups yet.</p>
          <button type="button" class="btn btn-primary" onclick={() => (activeTab = 'discover')}>
            Discover Groups
          </button>
        </div>
      {:else}
        <div class="group-list">
          {#each myGroups as group (group.id)}
            <GroupCard {group} onclick={() => openGroup(group.id)} />
          {/each}
        </div>
      {/if}
    {:else if activeTab === 'discover'}
      <div class="discover-search">
        <input
          type="text"
          class="input"
          placeholder="Search groups..."
          bind:value={searchQuery}
          oninput={handleSearch}
        />
      </div>

      {#if discoverLoading}
        <div class="tab-loading">
          <Spinner />
        </div>
      {:else if discoverGroups.length === 0}
        <div class="tab-empty">
          <p class="empty-text">No groups found</p>
        </div>
      {:else}
        <div class="group-list">
          {#each discoverGroups as group (group.id)}
            <GroupCard {group} onclick={() => openGroup(group.id)} />
          {/each}
        </div>
      {/if}
    {/if}
  </Tabs>
</div>

<style>
  .groups-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    width: 100%;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-block-end: var(--space-4);
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .tab-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-8);
  }

  .tab-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-4);
    padding: var(--space-12);
  }

  .empty-text {
    font-size: var(--text-base);
    color: var(--color-text-tertiary);
  }

  .discover-search {
    padding-block-end: var(--space-4);
  }

  .group-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }
</style>

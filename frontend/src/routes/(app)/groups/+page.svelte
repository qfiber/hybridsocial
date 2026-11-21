<script lang="ts">
  import { instanceName } from '$lib/stores/instance.js';
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import type { Group } from '$lib/api/types.js';
  import { getGroups, searchGroups } from '$lib/api/groups.js';
  import EntityCard from '$lib/components/entity/EntityCard.svelte';
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

  // My-Groups gets a client-side filter — the list is small and a
  // server round trip would feel laggy. Discover keeps the existing
  // server-side searchGroups call (debounced via handleSearch).
  function filterByQuery(list: Group[], q: string): Group[] {
    const needle = q.trim().toLowerCase();
    if (!needle) return list;
    return list.filter((g) => {
      const haystack = [g.name, g.description].filter(Boolean).join(' ').toLowerCase();
      return haystack.includes(needle);
    });
  }
</script>

<svelte:head>
  <title>Groups - {$instanceName}</title>
</svelte:head>

<div class="groups-page">
  <Tabs {tabs} bind:active={activeTab}>
    {#snippet header()}
    <div class="page-header">
      <h1 class="page-title">Groups</h1>
      <a href="/groups/new" class="btn btn-primary new-group-btn">New group</a>
    </div>

    <div class="search-bar">
      <svg class="search-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <circle cx="11" cy="11" r="8" />
        <line x1="21" y1="21" x2="16.65" y2="16.65" />
      </svg>
      <input
        type="search"
        class="search-input"
        placeholder={activeTab === 'discover' ? 'Search groups…' : 'Filter your groups…'}
        bind:value={searchQuery}
        oninput={handleSearch}
        aria-label="Search groups"
      />
      {#if searchQuery}
        <button type="button" class="search-clear" onclick={() => { searchQuery = ''; handleSearch(); }} aria-label="Clear search">
          <svg width="14" height="14" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="4" y1="4" x2="16" y2="16" />
            <line x1="16" y1="4" x2="4" y2="16" />
          </svg>
        </button>
      {/if}
    </div>
    {/snippet}
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
        {@const filteredMy = filterByQuery(myGroups, searchQuery)}
        {#if filteredMy.length === 0}
          <div class="tab-empty">
            <p class="empty-text">No groups match "{searchQuery}"</p>
          </div>
        {:else}
          <div class="group-grid">
            {#each filteredMy as group (group.id)}
              <EntityCard
                name={group.name}
                avatarUrl={group.avatar_url}
                coverUrl={group.header_url}
                description={group.description}
                badge={group.visibility === 'private' ? 'Private' : 'Public'}
                count={group.member_count}
                countLabel={group.member_count === 1 ? 'member' : 'members'}
                onclick={() => openGroup(group.id)}
              />
            {/each}
          </div>
        {/if}
      {/if}
    {:else if activeTab === 'discover'}
      {#if discoverLoading}
        <div class="tab-loading">
          <Spinner />
        </div>
      {:else if discoverGroups.length === 0}
        <div class="tab-empty">
          <p class="empty-text">No groups found</p>
        </div>
      {:else}
        <div class="group-grid">
          {#each discoverGroups as group (group.id)}
            <EntityCard
              name={group.name}
              avatarUrl={group.avatar_url}
              coverUrl={group.header_url}
              description={group.description}
              badge={group.visibility === 'private' ? 'Private' : 'Public'}
              count={group.member_count}
              countLabel={group.member_count === 1 ? 'member' : 'members'}
              onclick={() => openGroup(group.id)}
            />
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

  /* Search */
  .search-bar {
    position: relative;
    display: flex;
    align-items: center;
    margin-block-end: var(--space-4);
  }

  .search-icon {
    position: absolute;
    inset-inline-start: var(--space-3);
    color: var(--color-text-tertiary);
    pointer-events: none;
  }

  .search-input {
    width: 100%;
    padding: var(--space-3) var(--space-10);
    padding-inline-start: calc(var(--space-3) + 24px);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
  }

  .search-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft);
  }

  .search-clear {
    position: absolute;
    inset-inline-end: var(--space-3);
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    color: var(--color-text-tertiary);
    border-radius: var(--radius-full);
    cursor: pointer;
    padding: 0;
  }

  .search-clear:hover {
    color: var(--color-text);
    background: var(--color-surface);
  }

  /* 2-column grid that collapses to 1 column on narrow viewports —
     matches /pages so the directory listings feel uniform. */
  .group-grid {
    display: grid;
    grid-template-columns: 1fr;
    gap: var(--space-4);
  }

  @media (min-width: 720px) {
    .group-grid {
      grid-template-columns: 1fr 1fr;
    }
  }
</style>

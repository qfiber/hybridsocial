<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import type { Post, Identity, TrendingTag } from '$lib/api/types.js';
  import { getTrending, getTrendingAccounts } from '$lib/api/instance.js';
  import {
    followTag,
    unfollowTag,
    getFollowedTags,
    follow,
    unfollow,
    getRelationships,
  } from '$lib/api/accounts.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import DisplayName from '$lib/components/DisplayName.svelte';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import { t } from '$lib/stores/i18n.js';

  // Trending has three distinct modes so it isn't just a duplicate of the
  // Global feed. Tags is the default; the choice is remembered per device.
  type Mode = 'tags' | 'accounts' | 'posts';
  const MODE_KEY = 'hs-explore-trending-mode';
  const MODES: { id: Mode; labelKey: string }[] = [
    { id: 'tags', labelKey: 'explore.trending_tags' },
    { id: 'accounts', labelKey: 'explore.trending_accounts' },
    { id: 'posts', labelKey: 'explore.trending_posts' },
  ];
  let mode = $state<Mode>('tags');

  function changeMode(next: Mode) {
    if (mode === next) return;
    mode = next;
    try {
      localStorage.setItem(MODE_KEY, next);
    } catch {
      /* storage unavailable — the choice just won't persist */
    }
    void loadForMode();
  }

  // --- Tags -----------------------------------------------------------------
  let tags = $state<TrendingTag[]>([]);
  let followedTags = $state<Set<string>>(new Set());
  let tagsLoaded = false;
  let tagsLoading = $state(false);

  async function loadTags() {
    tagsLoading = true;
    try {
      const [tg, ft] = await Promise.all([getTrending(), getFollowedTags()]);
      tags = tg;
      followedTags = new Set(ft.map((x) => x.name.toLowerCase()));
      tagsLoaded = true;
    } finally {
      tagsLoading = false;
    }
  }

  async function toggleTag(name: string) {
    const key = name.toLowerCase();
    const wasFollowing = followedTags.has(key);
    const next = new Set(followedTags);
    wasFollowing ? next.delete(key) : next.add(key);
    followedTags = next; // optimistic
    try {
      wasFollowing ? await unfollowTag(name) : await followTag(name);
    } catch {
      const rb = new Set(followedTags);
      wasFollowing ? rb.add(key) : rb.delete(key);
      followedTags = rb;
    }
  }

  // --- Accounts -------------------------------------------------------------
  let accounts = $state<Identity[]>([]);
  let followingIds = $state<Set<string>>(new Set());
  let accountsLoaded = false;
  let accountsLoading = $state(false);

  async function loadAccounts() {
    accountsLoading = true;
    try {
      const list = await getTrendingAccounts();
      accounts = list;
      const ids = list.map((a) => a.id);
      if (ids.length) {
        const rels = await getRelationships(ids);
        followingIds = new Set(rels.filter((r) => r.following).map((r) => r.id));
      }
      accountsLoaded = true;
    } finally {
      accountsLoading = false;
    }
  }

  async function toggleFollow(acct: Identity) {
    const wasFollowing = followingIds.has(acct.id);
    const next = new Set(followingIds);
    wasFollowing ? next.delete(acct.id) : next.add(acct.id);
    followingIds = next; // optimistic
    try {
      wasFollowing ? await unfollow(acct.id) : await follow(acct.id);
    } catch {
      const rb = new Set(followingIds);
      wasFollowing ? rb.add(acct.id) : rb.delete(acct.id);
      followingIds = rb;
    }
  }

  // --- Posts ----------------------------------------------------------------
  let posts = $state<Post[]>([]);
  let postsLoaded = false;
  let postsLoading = $state(false);

  async function loadPosts() {
    postsLoading = true;
    try {
      const res = await api.get<any>('/api/v1/timelines/public?algorithm=trending&local=false');
      posts = Array.isArray(res) ? res : (res?.data ?? []);
      postsLoaded = true;
    } finally {
      postsLoading = false;
    }
  }

  // Load the active mode (once — switching back reuses cached data).
  function loadForMode() {
    if (mode === 'tags') return tagsLoaded ? undefined : loadTags();
    if (mode === 'accounts') return accountsLoaded ? undefined : loadAccounts();
    return postsLoaded ? undefined : loadPosts();
  }

  onMount(() => {
    try {
      const saved = localStorage.getItem(MODE_KEY);
      if (saved === 'tags' || saved === 'accounts' || saved === 'posts') mode = saved;
    } catch {
      /* ignore */
    }
    void loadForMode();
  });
</script>

<div class="et">
  <div class="et-tabs" role="tablist" aria-label={$t('explore.trending_sort')}>
    {#each MODES as m (m.id)}
      <button
        type="button"
        class="et-tab"
        class:on={mode === m.id}
        role="tab"
        aria-selected={mode === m.id}
        onclick={() => changeMode(m.id)}
      >
        {$t(m.labelKey)}
      </button>
    {/each}
  </div>

  {#if mode === 'tags'}
    {#if tagsLoading && tags.length === 0}
      <p class="et-status">{$t('common.loading')}</p>
    {:else if tags.length === 0}
      <p class="et-status">{$t('explore.trending_empty')}</p>
    {:else}
      <ul class="et-list">
        {#each tags as tag (tag.name)}
          {@const following = followedTags.has(tag.name.toLowerCase())}
          <li class="et-row">
            <a class="et-tag" href="/tags/{encodeURIComponent(tag.name)}">
              <span class="et-tag-name">#{tag.name}</span>
              {#if (tag.history || [])[0]?.uses}
                <span class="et-tag-count">{(tag.history || [])[0].uses} {$t('explore.posts_today')}</span>
              {/if}
            </a>
            <button
              type="button"
              class="et-follow"
              class:following
              aria-pressed={following}
              onclick={() => toggleTag(tag.name)}
            >
              {following ? $t('explore.following') : $t('explore.follow')}
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  {:else if mode === 'accounts'}
    {#if accountsLoading && accounts.length === 0}
      <p class="et-status">{$t('common.loading')}</p>
    {:else if accounts.length === 0}
      <p class="et-status">{$t('explore.trending_empty')}</p>
    {:else}
      <ul class="et-list">
        {#each accounts as acct (acct.id)}
          {@const following = followingIds.has(acct.id)}
          <li class="et-row">
            <a class="et-account" href="/@{acct.acct || acct.handle}">
              <Avatar src={acct.avatar_url} name={acct.display_name || acct.handle} size="md" />
              <span class="et-account-text">
                <span class="et-account-name"
                  ><DisplayName name={acct.display_name || acct.handle} emojis={acct.emojis} /></span
                >
                <span class="et-account-handle">@{acct.acct || acct.handle}</span>
              </span>
            </a>
            <button
              type="button"
              class="et-follow"
              class:following
              aria-pressed={following}
              onclick={() => toggleFollow(acct)}
            >
              {following ? $t('explore.following') : $t('explore.follow')}
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  {:else}
    {#if postsLoading && posts.length === 0}
      <p class="et-status">{$t('common.loading')}</p>
    {:else}
      <FeedList {posts} loading={false} hasMore={false} filterContext="public" />
    {/if}
  {/if}
</div>

<style>
  .et-tabs {
    display: flex;
    gap: var(--space-2, 8px);
    padding: var(--space-2, 8px) 0;
    position: sticky;
    inset-block-start: var(--header-height, 60px);
    z-index: 5;
    background: var(--color-surface-base, #fff);
  }

  .et-tab {
    padding: 6px 14px;
    border-radius: var(--radius-full, 999px);
    border: 1px solid var(--color-border);
    background: transparent;
    color: var(--color-text-secondary);
    font-weight: 600;
    font-size: var(--text-sm, 0.875rem);
    cursor: pointer;
    transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;
  }

  .et-tab:hover {
    background: var(--color-surface-hover, rgba(0, 0, 0, 0.06));
  }

  .et-tab.on {
    background: var(--color-primary);
    border-color: var(--color-primary);
    color: var(--color-on-primary, #fff);
  }

  .et-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
  }

  .et-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3, 12px);
    padding: var(--space-3, 12px) var(--space-1, 4px);
    border-block-end: 1px solid var(--color-border);
  }

  .et-tag {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    text-decoration: none;
    color: inherit;
  }

  .et-tag-name {
    font-weight: 700;
    color: var(--color-primary);
  }

  .et-tag-count,
  .et-account-handle {
    font-size: var(--text-xs, 0.75rem);
    color: var(--color-text-tertiary);
  }

  .et-account {
    display: flex;
    align-items: center;
    gap: var(--space-3, 12px);
    min-width: 0;
    text-decoration: none;
    color: inherit;
  }

  .et-account-text {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
  }

  .et-account-name {
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .et-follow {
    flex: 0 0 auto;
    padding: 6px 16px;
    border-radius: var(--radius-full, 999px);
    border: 1px solid var(--color-primary);
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
    font-weight: 600;
    font-size: var(--text-sm, 0.875rem);
    cursor: pointer;
  }

  /* Following state = outlined, so "unfollow on click" reads as the toggle. */
  .et-follow.following {
    background: transparent;
    color: var(--color-text);
    border-color: var(--color-border);
  }

  .et-status {
    padding: var(--space-5, 24px);
    text-align: center;
    color: var(--color-text-tertiary);
  }
</style>

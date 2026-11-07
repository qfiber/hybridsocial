<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import { getPromotedUsers, getPromotionPricing, purchasePromotion, formatPrice } from '$lib/api/promotions.js';
  import type { PromotedUser, PromotionPricing } from '$lib/api/promotions.js';
  import { getSuggestions, follow, unfollow, unfollowTag, getRelationships } from '$lib/api/accounts.js';
  import type { Identity, PostEmoji } from '$lib/api/types.js';
  import DisplayName from '$lib/components/DisplayName.svelte';
  import { t } from '$lib/stores/i18n.js';
  // Plain (non-reactive) translate for imperative use in event handlers
  // (toasts) where the $t store subscription isn't available.
  import { t as translate } from '$lib/utils/i18n.js';

  // A person shown in "Recommended Accounts". Merged from promoted
  // users, the server's /suggestions endpoint, and any passed-in prop.
  interface SidebarAccount {
    id?: string;
    handle: string;
    acct?: string;
    display_name: string | null;
    avatar_url: string | null;
    emojis?: PostEmoji[];
    promoted?: boolean;
  }

  let {
    suggestions = []
  }: {
    suggestions?: SidebarAccount[];
  } = $props();

  // Distinguishes "still loading" from "genuinely empty" so widgets can
  // show skeletons instead of a misleading empty state during fetch.
  let loaded = $state(false);

  interface TrendingTag {
    tag: string;
    people: number;
    posts: number;
    history: number[];
  }
  let trending: TrendingTag[] = $state([]);

  interface FollowedTag {
    id: string;
    name: string;
  }
  let followedTags: FollowedTag[] = $state([]);

  let promotedUsers: PromotedUser[] = $state([]);
  let suggestedUsers: SidebarAccount[] = $state([]);
  let pricing: PromotionPricing | null = $state(null);
  let showPromoModal = $state(false);

  // Follow state keyed by account id. `following` tracks the current
  // relationship (prefilled from getRelationships); `followBusy` guards
  // an in-flight request so the button can't be double-fired.
  let following = $state<Record<string, boolean>>({});
  let followBusy = $state<Record<string, boolean>>({});

  async function toggleFollow(acct: SidebarAccount, e: MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    const id = acct.id;
    if (!id || followBusy[id]) return;
    followBusy = { ...followBusy, [id]: true };
    const wasFollowing = following[id];
    // Optimistic flip; revert on failure.
    following = { ...following, [id]: !wasFollowing };
    try {
      if (wasFollowing) {
        await unfollow(id);
      } else {
        await follow(id);
        addToast(translate('discover.following_toast', { name: acct.display_name || acct.handle }), 'success');
      }
    } catch {
      following = { ...following, [id]: wasFollowing };
      addToast(translate('discover.follow_failed'), 'error');
    } finally {
      followBusy = { ...followBusy, [id]: false };
    }
  }

  async function handleUnfollowTag(tag: FollowedTag, e: MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    const prev = followedTags;
    // Optimistic removal.
    followedTags = followedTags.filter(t => t.id !== tag.id);
    try {
      await unfollowTag(tag.name);
    } catch {
      followedTags = prev;
      addToast('Could not unfollow hashtag', 'error');
    }
  }

  interface NewUser {
    id: string;
    handle: string;
    acct?: string;
    display_name: string | null;
    avatar_url: string | null;
    emojis?: PostEmoji[];
    bio: string | null;
    joined_at: string;
  }
  let newUsers: NewUser[] = $state([]);

  // Instance metadata shown in the footer. Fetched from /instance/info
  // so admins who configure a fork's source_url (or bump the version
  // in mix.exs) don't need a frontend redeploy to see it.
  let instanceVersion = $state<string | null>(null);
  let instanceBuildSha = $state<string>('');
  let instanceSourceUrl = $state<string>('https://github.com/qfiber/hybridsocial');

  // Frontend build commit, baked in at build time by Vite. instanceBuildSha
  // (below) is the BACKEND's build commit from the API — the two are deployed
  // independently and can differ, so the footer shows both (web · api).
  const webSha =
    import.meta.env.VITE_WEB_SHA && import.meta.env.VITE_WEB_SHA !== 'dev'
      ? String(import.meta.env.VITE_WEB_SHA)
      : '';

  // Promoted first, then server suggestions, then any prop-passed
  // accounts — deduped by handle so a promoted account can't appear twice.
  let allPool = $derived.by(() => {
    const seen = new Set<string>();
    const out: SidebarAccount[] = [];
    for (const p of [...promotedUsers, ...suggestedUsers, ...suggestions]) {
      if (seen.has(p.handle)) continue;
      seen.add(p.handle);
      out.push(p);
    }
    return out;
  });

  // Shuffle and rotate visible suggestions every 2 minutes. Rotation
  // pauses while the user is hovering/focused inside the section so the
  // list can't reshuffle out from under a click.
  let shuffleTick = $state(0);
  let rotationPaused = $state(false);
  let rotateInterval: ReturnType<typeof setInterval> | null = null;

  onMount(() => {
    rotateInterval = setInterval(() => {
      if (!rotationPaused) shuffleTick++;
    }, 120_000);
    return () => { if (rotateInterval) clearInterval(rotateInterval); };
  });

  function seededShuffle<T>(arr: T[], seed: number): T[] {
    const copy = [...arr];
    let s = seed;
    for (let i = copy.length - 1; i > 0; i--) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      const j = s % (i + 1);
      [copy[i], copy[j]] = [copy[j], copy[i]];
    }
    return copy;
  }

  let allSuggestions = $derived(seededShuffle(allPool, shuffleTick + 1).slice(0, 5));

  function timeAgo(dateStr: string): string {
    const diff = Math.floor((Date.now() - new Date(dateStr).getTime()) / 1000);
    if (diff < 60) return 'just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    if (diff < 604800) return `${Math.floor(diff / 86400)}d ago`;
    return new Date(dateStr).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  }

  onMount(async () => {
    try {
      const [users, suggested, pricingData, newUsersData, trendingData, followedTagsData] = await Promise.all([
        getPromotedUsers().catch(() => [] as PromotedUser[]),
        getSuggestions().catch(() => [] as Identity[]),
        getPromotionPricing().catch(() => null),
        api.get<NewUser[]>('/api/v1/directory/new', { limit: '5' }).catch(() => [] as NewUser[]),
        api.get<{ name: string; score: number; metadata: { post_count?: number; unique_accounts?: number; history?: number[] } }[]>('/api/v1/trends/tags')
          .then(tags => tags.map(t => ({
            tag: t.name,
            people: t.metadata?.unique_accounts ?? t.metadata?.post_count ?? 0,
            posts: t.metadata?.post_count ?? 0,
            history: Array.isArray(t.metadata?.history) ? t.metadata!.history! : []
          })))
          .catch(() => [] as TrendingTag[]),
        api.get<FollowedTag[]>('/api/v1/accounts/followed_tags').catch(() => [] as FollowedTag[]),
      ]);
      promotedUsers = users;
      suggestedUsers = suggested.map(s => ({
        id: s.id,
        handle: s.handle,
        acct: s.acct,
        display_name: s.display_name,
        avatar_url: s.avatar_url,
        emojis: s.emojis
      }));
      pricing = pricingData;
      newUsers = newUsersData;
      trending = trendingData;
      followedTags = followedTagsData;
    } catch {
      // Sidebar is non-critical
    } finally {
      loaded = true;
    }

    // Prefill follow state for everyone with an id so the button shows
    // the right label. Best-effort — the button still works without it.
    const ids = [
      ...promotedUsers.map(p => p.id),
      ...suggestedUsers.map(s => s.id),
      ...newUsers.map(u => u.id)
    ].filter((id): id is string => !!id);
    if (ids.length > 0) {
      try {
        const rels = await getRelationships([...new Set(ids)]);
        const map: Record<string, boolean> = {};
        for (const r of rels) map[r.id] = r.following;
        following = map;
      } catch {
        // ignore — buttons default to "Follow"
      }
    }

    // Instance meta for the footer. Non-blocking — if this 404s or
    // errors, the footer just omits the version/source line.
    try {
      const info = await api.get<{
        version?: string;
        source_url?: string;
        build?: { sha?: string; date?: string };
      }>('/api/v1/instance/info');
      if (info?.version) instanceVersion = info.version;
      if (info?.source_url) instanceSourceUrl = info.source_url;
      // The exact commit the running build was made from. 'dev' = a build
      // that wasn't stamped (e.g. local), so we just omit it.
      if (info?.build?.sha && info.build.sha !== 'dev') instanceBuildSha = info.build.sha;
    } catch {
      // ignore
    }
  });

  // Build a smooth SVG path from a 7-point history series using
  // Catmull-Rom-style cubic bezier control points. Inset vertically
  // so the rounded stroke doesn't clip at the viewBox edges.
  function sparklinePath(history: number[], w = 56, h = 24): string {
    if (!history || history.length === 0) return '';
    const pad = 2;
    const drawH = h - pad * 2;
    const max = Math.max(1, ...history);
    const min = Math.min(...history);
    const range = max - min || 1;
    const step = history.length === 1 ? 0 : w / (history.length - 1);
    const pts = history.map((v, i) => ({
      x: i * step,
      y: pad + drawH - ((v - min) / range) * drawH
    }));
    if (pts.length < 2) return `M ${pts[0].x.toFixed(1)} ${pts[0].y.toFixed(1)}`;
    const tension = 0.4;
    let d = `M ${pts[0].x.toFixed(2)} ${pts[0].y.toFixed(2)}`;
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[i - 1] ?? pts[i];
      const p1 = pts[i];
      const p2 = pts[i + 1];
      const p3 = pts[i + 2] ?? p2;
      const c1x = p1.x + (p2.x - p0.x) * tension * 0.5;
      const c1y = p1.y + (p2.y - p0.y) * tension * 0.5;
      const c2x = p2.x - (p3.x - p1.x) * tension * 0.5;
      const c2y = p2.y - (p3.y - p1.y) * tension * 0.5;
      d += ` C ${c1x.toFixed(2)} ${c1y.toFixed(2)}, ${c2x.toFixed(2)} ${c2y.toFixed(2)}, ${p2.x.toFixed(2)} ${p2.y.toFixed(2)}`;
    }
    return d;
  }

  // Skip the sparkline when there's no variation across the 7-h
  // window — every bucket the same value (usually all zeros for tags
  // posted more than 7 h ago) renders as a meaningless flat line at
  // the chart edge. Better to draw nothing than visual noise.
  function hasSparklineSignal(history: number[]): boolean {
    if (!history || history.length < 2) return false;
    const max = Math.max(...history);
    const min = Math.min(...history);
    return max > min;
  }

  // 1234 -> "1.2K", 2_500_000 -> "2.5M". Keeps count lines compact and
  // scannable instead of printing raw six-digit numbers in a tight column.
  const compactFmt = new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 1 });
  function compact(n: number): string {
    return compactFmt.format(n ?? 0);
  }

  async function handlePurchase() {
    try {
      await purchasePromotion();
      showPromoModal = false;
      addToast(translate('promo.activated'), 'success');
      promotedUsers = await getPromotedUsers().catch(() => []);
    } catch (err: unknown) {
      const error = err as { body?: { error?: string } };
      if (error?.body?.error === 'promotions.already_active') {
        addToast(translate('promo.already_active'), 'error');
      } else {
        addToast(translate('promo.purchase_failed'), 'error');
      }
    }
  }
</script>

{#snippet skeletonRows(count: number, avatar: boolean)}
  <ul class="skeleton-list" aria-hidden="true">
    {#each Array(count) as _, i (i)}
      <li class="skel-row" class:with-avatar={avatar}>
        {#if avatar}<span class="skel-avatar"></span>{/if}
        <span class="skel-lines">
          <span class="skel-line skel-line-lg"></span>
          <span class="skel-line skel-line-sm"></span>
        </span>
      </li>
    {/each}
  </ul>
{/snippet}

{#snippet followBtn(acct: SidebarAccount)}
  {#if acct.id}
    {@const id = acct.id}
    <button
      type="button"
      class="follow-btn"
      class:is-following={following[id]}
      onclick={(e) => toggleFollow(acct, e)}
      disabled={followBusy[id]}
      aria-label={following[id]
        ? $t('discover.unfollow_aria', { name: acct.display_name || acct.handle })
        : $t('discover.follow_aria', { name: acct.display_name || acct.handle })}
    >
      {following[id] ? $t('profile.following') : $t('profile.follow')}
    </button>
  {/if}
{/snippet}

<aside class="right-sidebar" aria-label={$t('discover.title')}>
  <section class="sidebar-section">
    <header class="section-header">
      <h3 class="section-title">
        <svg class="section-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/>
          <polyline points="16 7 22 7 22 13"/>
        </svg>
        {$t('discover.trending')}
      </h3>
    </header>
    {#if !loaded}
      {@render skeletonRows(5, false)}
    {:else if trending.length > 0}
      <ul class="trend-list">
        {#each trending.slice(0, 10) as item, i (item.tag)}
          <li>
            <a href="/tags/{encodeURIComponent(item.tag)}" class="trend-item">
              <span class="trend-rank">{i + 1}</span>
              <div class="trend-text">
                <span class="trend-tag">#{item.tag}</span>
                <span class="trend-meta">
                  {$t('discover.people_talking', { count: item.people, num: compact(item.people) })}{#if item.posts > 0} · <span class="tnum">{$t('discover.posts_count', { count: item.posts, num: compact(item.posts) })}</span>{/if}
                </span>
              </div>
              {#if hasSparklineSignal(item.history)}
                <svg class="trend-spark" viewBox="0 0 56 24" preserveAspectRatio="none" aria-hidden="true">
                  <path d={sparklinePath(item.history)} fill="none" stroke="var(--color-primary)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" />
                </svg>
              {/if}
            </a>
          </li>
        {/each}
      </ul>
      <a href="/explore?tab=trending" class="section-link">{$t('discover.view_all_trends')}</a>
    {:else}
      <p class="empty-text">{$t('discover.no_trending')}</p>
    {/if}
  </section>

  <section class="sidebar-section">
    <header class="section-header">
      <h3 class="section-title">
        <svg class="section-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <line x1="4" y1="9" x2="20" y2="9"/>
          <line x1="4" y1="15" x2="20" y2="15"/>
          <line x1="10" y1="3" x2="8" y2="21"/>
          <line x1="16" y1="3" x2="14" y2="21"/>
        </svg>
        {$t('discover.followed_hashtags')}
      </h3>
    </header>
    {#if !loaded}
      {@render skeletonRows(4, false)}
    {:else if followedTags.length > 0}
      <ul class="trend-list">
        {#each followedTags.slice(0, 8) as tag (tag.id)}
          <li class="tag-row">
            <a href="/tags/{encodeURIComponent(tag.name)}" class="trend-item tag-link">
              <div class="trend-text">
                <span class="trend-tag">#{tag.name}</span>
              </div>
            </a>
            <button
              type="button"
              class="tag-unfollow"
              onclick={(e) => handleUnfollowTag(tag, e)}
              aria-label={$t('discover.unfollow_tag', { tag: tag.name })}
              title={$t('discover.unfollow_tag', { tag: tag.name })}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
              </svg>
            </button>
          </li>
        {/each}
      </ul>
      <a href="/explore?tab=trending" class="section-link">{$t('discover.find_hashtags')}</a>
    {:else}
      <p class="empty-text">{$t('discover.no_hashtags')}</p>
    {/if}
  </section>

  <section
    class="sidebar-section"
    onmouseenter={() => rotationPaused = true}
    onmouseleave={() => rotationPaused = false}
    onfocusin={() => rotationPaused = true}
    onfocusout={() => rotationPaused = false}
    aria-label={$t('discover.recommended')}
  >
    <header class="section-header">
      <h3 class="section-title">
        <svg class="section-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
          <circle cx="9" cy="7" r="4"/>
          <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
          <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
        </svg>
        {$t('discover.recommended')}
      </h3>
    </header>
    {#if !loaded}
      {@render skeletonRows(4, true)}
    {:else if allSuggestions.length > 0}
      {#key shuffleTick}
      <ul class="suggestions-list suggestions-enter">
        {#each allSuggestions as person, i (person.handle)}
          <li class="suggestion-stagger" style="animation-delay: {i * 60}ms">
            <div class="suggestion-item">
              <a href="/@{person.handle}" class="suggestion-link">
                <div class="suggestion-avatar">
                  <img src={person.avatar_url || '/images/default-avatar.svg'} alt="" loading="lazy" class="suggestion-img" />
                </div>
                <div class="suggestion-info">
                  <span class="suggestion-name">
                    <DisplayName name={person.display_name} fallback={person.handle} emojis={person.emojis} />
                    {#if person.promoted}
                      <span class="promoted-badge">{$t('discover.promoted')}</span>
                    {/if}
                  </span>
                  <span class="suggestion-handle">@{person.acct || person.handle}</span>
                </div>
              </a>
              {@render followBtn(person)}
            </div>
          </li>
        {/each}
      </ul>
      {/key}
      <a href="/directory" class="section-link">{$t('discover.find_people')}</a>
    {:else}
      <p class="empty-text">{$t('discover.no_suggestions')}</p>
    {/if}
  </section>

  {#if !loaded || newUsers.length > 0}
    <section class="sidebar-section">
      <header class="section-header">
        <h3 class="section-title">
          <svg class="section-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/>
            <circle cx="9" cy="7" r="4"/>
            <line x1="19" y1="8" x2="19" y2="14"/><line x1="22" y1="11" x2="16" y2="11"/>
          </svg>
          {$t('discover.new_members')}
        </h3>
      </header>
      {#if !loaded}
        {@render skeletonRows(4, true)}
      {:else}
        <ul class="new-users-list">
          {#each newUsers as user (user.id)}
            <li>
              <div class="new-user-item">
                <a href="/@{user.handle}" class="new-user-link">
                  <div class="new-user-avatar">
                    <img src={user.avatar_url || '/images/default-avatar.svg'} alt="" loading="lazy" class="new-user-img" />
                  </div>
                  <div class="new-user-info">
                    <span class="new-user-name"><DisplayName name={user.display_name} fallback={user.handle} emojis={user.emojis} /></span>
                    <span class="new-user-meta">@{user.acct || user.handle} &middot; {timeAgo(user.joined_at)}</span>
                  </div>
                </a>
                {@render followBtn(user)}
              </div>
            </li>
          {/each}
        </ul>
        <a href="/directory" class="section-link">{$t('discover.see_more')}</a>
      {/if}
    </section>
  {/if}

  {#if pricing?.enabled && pricing?.payment_configured}
    <section class="sidebar-section promo-cta">
      <div class="promo-cta-icon">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
        </svg>
      </div>
      <h4 class="promo-cta-title">{$t('promo.cta_title')}</h4>
      <p class="promo-cta-text">
        {$t('promo.cta_text', { days: pricing.duration_days })}
      </p>
      <button class="promo-cta-btn" onclick={() => showPromoModal = true}>
        {$t('promo.cta_button', { price: formatPrice(pricing.price_cents, pricing.currency) })}
      </button>
    </section>
  {/if}

  <section class="sidebar-footer">
    {#if $page.data?.instance?.description}
      <p
        class="footer-about"
        style="font-size: var(--text-xs); line-height: 1.5; color: var(--color-text-secondary); margin-block-end: var(--space-3);"
      >
        {$page.data.instance.description}
      </p>
    {/if}
    <nav class="footer-links" aria-label={$t('discover.footer_label')}>
      <a href="/legal/about" class="footer-link">{$t('footer.about')}</a>
      <span class="footer-dot" aria-hidden="true">&middot;</span>
      <a href="/legal/privacy" class="footer-link">{$t('footer.privacy')}</a>
      <span class="footer-dot" aria-hidden="true">&middot;</span>
      <a href="/legal/terms" class="footer-link">{$t('footer.terms')}</a>
      <span class="footer-dot" aria-hidden="true">&middot;</span>
      <button
        type="button"
        class="footer-link footer-link-button"
        onclick={() => window.dispatchEvent(new CustomEvent('open-shortcuts-help'))}
        title={$t('footer.shortcuts_title')}
      >
        {$t('footer.shortcuts')}
      </button>
    </nav>
    <p class="footer-text">
      <a href={instanceSourceUrl} target="_blank" rel="noopener noreferrer" class="footer-link">
        <svg class="footer-gh-icon" width="12" height="12" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
          <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.012 8.012 0 0 0 16 8c0-4.42-3.58-8-8-8z"/>
        </svg>
        HybridSocial
      </a>
      {#if instanceVersion}<span class="footer-version">v{instanceVersion}</span>{/if}
    </p>
    {#if webSha || instanceBuildSha}
      <div class="footer-build">
        {#if webSha}<span><span class="footer-build-label">web</span>{webSha}</span>{/if}
        {#if instanceBuildSha}<span><span class="footer-build-label">api</span>{instanceBuildSha}</span>{/if}
      </div>
    {/if}
  </section>
</aside>

{#if showPromoModal && pricing}
  <div class="modal-overlay" onclick={() => showPromoModal = false} role="presentation">
    <div class="modal-card" onclick={(e) => e.stopPropagation()} role="dialog" aria-labelledby="promo-modal-title">
      <button class="modal-close" onclick={() => showPromoModal = false} aria-label={$t('common.close')}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
        </svg>
      </button>

      <div class="modal-icon">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
        </svg>
      </div>

      <h3 id="promo-modal-title" class="modal-title">{$t('promo.modal_title')}</h3>
      <p class="modal-desc">
        {$t('promo.modal_desc', { days: pricing.duration_days })}
      </p>

      <div class="modal-pricing">
        <div class="modal-price">{formatPrice(pricing.price_cents, pricing.currency)}</div>
        <div class="modal-period">{$t('promo.for_days', { days: pricing.duration_days })}</div>
      </div>

      <ul class="modal-features">
        <li>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
          {$t('promo.feature_featured')}
        </li>
        <li>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
          {$t('promo.feature_badge')}
        </li>
        <li>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
          {$t('promo.feature_reach')}
        </li>
        <li>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
          {$t('promo.feature_active')}
        </li>
      </ul>

      <button class="modal-buy-btn" onclick={handlePurchase}>
        {$t('promo.purchase_button')}
      </button>

      <p class="modal-note">
        {$t('promo.note')}
      </p>
    </div>
  </div>
{/if}

<style>
  .right-sidebar {
    position: sticky;
    top: calc(var(--header-height) + var(--space-8));
    height: calc(100vh - var(--header-height) - var(--space-8));
    padding: var(--space-2) 0;
    overflow-y: auto;
  }

  .sidebar-section {
    margin-block-end: var(--space-4);
    background: var(--color-surface-container-lowest);
    border-radius: var(--radius-xl);
    padding: var(--space-5);
    border: 1px solid var(--color-border);
    box-shadow: var(--shadow-sm);
  }

  .section-title {
    font-family: var(--font-headline);
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-on-surface);
    margin-block-end: var(--space-3);
  }

  .trend-list,
  .suggestions-list {
    display: flex;
    flex-direction: column;
  }

  .section-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-3);
  }

  .section-icon {
    color: var(--color-primary);
    margin-inline-end: var(--space-1);
    vertical-align: -2px;
  }

  .section-link {
    display: block;
    margin-block-start: var(--space-2);
    padding-block-start: var(--space-2);
    color: var(--color-primary);
    font-size: var(--text-sm);
    font-weight: 600;
    text-decoration: none;
  }

  .section-link:hover,
  .section-link:focus-visible {
    text-decoration: underline;
  }

  /* Entrance animations only when the user hasn't asked for reduced
     motion. Without the guard the 2-minute reshuffle re-runs the whole
     slide-in, which is exactly the kind of unsolicited motion the
     preference is meant to suppress. */
  @media (prefers-reduced-motion: no-preference) {
    .suggestions-enter {
      animation: suggestions-fade-in 0.3s ease;
    }

    .suggestion-stagger {
      animation: suggestion-slide-in 0.3s ease both;
    }
  }

  @keyframes suggestions-fade-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes suggestion-slide-in {
    from {
      opacity: 0;
      transform: translateX(-10px);
    }
    to {
      opacity: 1;
      transform: translateX(0);
    }
  }

  /* ---- Skeleton loading rows ---- */
  .skeleton-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .skel-row {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    margin-inline: calc(-1 * var(--space-3));
  }

  .skel-avatar {
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    flex-shrink: 0;
    background: var(--color-border);
  }

  .skel-lines {
    display: flex;
    flex-direction: column;
    gap: 6px;
    flex: 1;
    min-width: 0;
  }

  .skel-line {
    height: 10px;
    border-radius: var(--radius-sm);
    background: var(--color-border);
  }

  .skel-line-lg { width: 65%; }
  .skel-line-sm { width: 40%; }

  @media (prefers-reduced-motion: no-preference) {
    .skel-avatar,
    .skel-line {
      animation: skeleton-pulse 1.5s ease-in-out infinite;
    }
  }

  @keyframes skeleton-pulse {
    0%, 100% { opacity: 0.4; }
    50% { opacity: 0.7; }
  }

  .trend-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    margin-inline: calc(-1 * var(--space-3));
    text-decoration: none;
    color: var(--color-on-surface);
    border-radius: var(--radius-lg);
    transition: background var(--transition-fast);
  }

  .trend-item:hover,
  .trend-item:focus-visible {
    text-decoration: none;
    background: var(--color-surface-container-low);
  }

  .trend-rank {
    flex-shrink: 0;
    width: 1.25rem;
    font-family: var(--font-headline);
    font-size: var(--text-sm);
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--color-on-surface-variant);
    text-align: center;
  }

  .tnum {
    font-variant-numeric: tabular-nums;
  }

  .trend-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }

  .trend-tag {
    font-weight: 700;
    font-size: var(--text-sm);
    color: var(--color-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .trend-meta {
    font-size: var(--text-xs);
    color: var(--color-on-surface-variant);
  }

  .trend-spark {
    width: 56px;
    height: 24px;
    flex-shrink: 0;
    opacity: 0.75;
  }

  .trend-item:hover .trend-spark {
    opacity: 1;
  }

  .suggestion-item {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    margin-inline: calc(-1 * var(--space-3));
    border-radius: var(--radius-lg);
    transition: background var(--transition-fast);
  }

  .suggestion-item:hover,
  .suggestion-item:focus-within {
    background: var(--color-surface-container-low);
  }

  .suggestion-link {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    flex: 1;
    min-width: 0;
    text-decoration: none;
    color: var(--color-on-surface);
  }

  .suggestion-avatar {
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    background: var(--color-secondary-container);
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .suggestion-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .suggestion-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .suggestion-name {
    font-size: var(--text-sm);
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .promoted-badge {
    font-size: 0.6rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-primary);
    background: var(--color-secondary-container);
    padding: 1px 5px;
    border-radius: var(--radius-full);
    flex-shrink: 0;
  }

  .suggestion-handle {
    font-size: var(--text-xs);
    color: var(--color-on-surface-variant);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* ---- Inline follow button (Recommended Accounts + New Members) ---- */
  .follow-btn {
    flex-shrink: 0;
    padding: 5px var(--space-3);
    border: 1px solid var(--color-primary);
    border-radius: var(--radius-full);
    background: var(--color-primary);
    color: var(--color-on-primary);
    font-size: var(--text-xs);
    font-weight: 600;
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast),
      border-color var(--transition-fast), opacity var(--transition-fast);
  }

  .follow-btn:hover {
    box-shadow: var(--shadow-sm);
  }

  .follow-btn:disabled {
    opacity: 0.6;
    cursor: default;
  }

  /* Following state: quiet outline so "Following" reads as done, and a
     hover that hints at the unfollow action. */
  .follow-btn.is-following {
    background: transparent;
    color: var(--color-on-surface-variant);
    border-color: var(--color-border);
  }

  .follow-btn.is-following:hover {
    border-color: var(--color-destructive, #dc2626);
    color: var(--color-destructive, #dc2626);
    box-shadow: none;
  }

  .empty-text {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  /* ---- New Members ---- */
  .new-users-list {
    display: flex;
    flex-direction: column;
  }

  .new-user-item {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    margin-inline: calc(-1 * var(--space-3));
    border-radius: var(--radius-lg);
    transition: background var(--transition-fast);
  }

  .new-user-item:hover,
  .new-user-item:focus-within {
    background: var(--color-surface-container-low);
  }

  .new-user-link {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    flex: 1;
    min-width: 0;
    text-decoration: none;
    color: var(--color-on-surface);
  }

  .new-user-avatar {
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    background: var(--color-secondary-container);
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .new-user-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .new-user-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }

  .new-user-name {
    font-size: var(--text-sm);
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .new-user-meta {
    font-size: var(--text-xs);
    color: var(--color-on-surface-variant);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* ---- Followed hashtag row with unfollow affordance ---- */
  .tag-row {
    display: flex;
    align-items: center;
  }

  .tag-link {
    flex: 1;
    min-width: 0;
  }

  .tag-unfollow {
    flex-shrink: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    padding: 0;
    border: none;
    border-radius: var(--radius-full);
    background: transparent;
    color: var(--color-text-tertiary);
    cursor: pointer;
    opacity: 0;
    transition: opacity var(--transition-fast), background var(--transition-fast), color var(--transition-fast);
  }

  /* Reveal on hover/focus of the row; always visible on touch (no hover). */
  .tag-row:hover .tag-unfollow,
  .tag-row:focus-within .tag-unfollow {
    opacity: 1;
  }

  .tag-unfollow:hover,
  .tag-unfollow:focus-visible {
    background: var(--color-surface-container-low);
    color: var(--color-destructive, #dc2626);
  }

  @media (hover: none) {
    .tag-unfollow {
      opacity: 1;
    }
  }

  /* ---- Promote CTA ---- */
  .promo-cta {
    background: linear-gradient(180deg, var(--color-secondary-container) 0%, var(--color-surface-container-lowest) 100%);
    text-align: center;
  }

  .promo-cta-icon {
    color: var(--color-primary);
    margin-block-end: var(--space-2);
  }

  .promo-cta-title {
    font-family: var(--font-headline);
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--color-on-surface);
    margin-block-end: var(--space-1);
  }

  .promo-cta-text {
    font-size: var(--text-xs);
    color: var(--color-on-surface-variant);
    line-height: 1.4;
    margin-block-end: var(--space-3);
  }

  .promo-cta-btn {
    display: block;
    width: 100%;
    padding: var(--space-2) var(--space-3);
    background: var(--gradient-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: var(--radius-full);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    transition: box-shadow var(--transition-fast), transform 0.15s ease;
  }

  .promo-cta-btn:hover {
    box-shadow: var(--shadow-md);
  }

  .promo-cta-btn:active {
    transform: scale(0.98);
  }

  /* ---- Modal ---- */
  .modal-overlay {
    position: fixed;
    inset: 0;
    background: var(--color-overlay);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    padding: var(--space-4);
    animation: fadeIn 0.2s ease;
  }

  .modal-card {
    background: var(--color-surface-container-lowest);
    border-radius: var(--radius-xl);
    padding: var(--space-8);
    max-width: 420px;
    width: 100%;
    position: relative;
    box-shadow: var(--shadow-xl);
    animation: scaleIn 0.25s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes scaleIn {
    from { opacity: 0; transform: scale(0.95) translateY(8px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .modal-close {
    position: absolute;
    top: var(--space-4);
    inset-inline-end: var(--space-4);
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
    padding: var(--space-1);
    border-radius: var(--radius-full);
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .modal-close:hover {
    color: var(--color-on-surface);
    background: var(--color-surface-container-low);
  }

  .modal-icon {
    display: flex;
    justify-content: center;
    margin-block-end: var(--space-4);
  }

  .modal-title {
    font-family: var(--font-headline);
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-on-surface);
    text-align: center;
    margin-block-end: var(--space-2);
  }

  .modal-desc {
    font-size: var(--text-sm);
    color: var(--color-on-surface-variant);
    text-align: center;
    line-height: 1.5;
    margin-block-end: var(--space-5);
  }

  .modal-pricing {
    text-align: center;
    padding: var(--space-4);
    background: var(--color-surface-container-low);
    border-radius: var(--radius-xl);
    margin-block-end: var(--space-5);
  }

  .modal-price {
    font-family: var(--font-headline);
    font-size: var(--text-3xl);
    font-weight: 800;
    color: var(--color-on-surface);
  }

  .modal-period {
    font-size: var(--text-sm);
    color: var(--color-on-surface-variant);
  }

  .modal-features {
    list-style: none;
    padding: 0;
    margin: 0 0 var(--space-6) 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .modal-features li {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-on-surface);
  }

  .modal-features li svg {
    flex-shrink: 0;
  }

  .modal-buy-btn {
    display: block;
    width: 100%;
    padding: var(--space-3);
    background: var(--gradient-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: var(--radius-full);
    font-size: var(--text-base);
    font-weight: 600;
    cursor: pointer;
    transition: box-shadow var(--transition-fast), transform 0.15s ease;
  }

  .modal-buy-btn:hover {
    box-shadow: var(--shadow-md);
  }

  .modal-buy-btn:active {
    transform: scale(0.98);
  }

  .modal-note {
    text-align: center;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-3);
  }

  /* ---- Footer ---- */
  .sidebar-footer {
    padding: var(--space-4) var(--space-2) 0;
  }

  .footer-links {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    margin-block-end: var(--space-2);
  }

  .footer-link {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-decoration: none;
  }

  .footer-link:hover {
    color: var(--color-primary);
    text-decoration: underline;
  }

  .footer-link-button {
    background: transparent;
    border: none;
    padding: 0;
    cursor: pointer;
    /* `font: inherit` (shorthand) also resets font-size to inherit
       from the <nav>, which has no font-size declared and so falls
       back to the root 1rem. That clobbered the `var(--text-xs)`
       on `.footer-link` and made "Shortcuts" render larger than the
       neighbouring About / Privacy / Terms links. Only inherit the
       family/weight/line-height we actually want; keep the size and
       color from the .footer-link rule. */
    font-family: inherit;
    font-weight: inherit;
    line-height: inherit;
  }

  .footer-dot {
    color: var(--color-text-tertiary);
    font-size: var(--text-xs);
  }

  .footer-text {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .footer-text .footer-link {
    display: inline-flex;
    align-items: center;
    gap: 5px;
  }

  .footer-gh-icon {
    vertical-align: -1px;
  }

  .footer-version {
    font-family: var(--font-mono);
    color: var(--color-text-secondary);
  }

  /* Build commits, stacked under the version so the row stays clean:
       web  d7801d5
       api  7e62b19  */
  .footer-build {
    display: flex;
    flex-direction: column;
    gap: 1px;
    margin-block-start: 5px;
    font-family: var(--font-mono);
    font-size: 0.68rem;
    line-height: 1.5;
    color: var(--color-text-tertiary);
  }

  .footer-build-label {
    display: inline-block;
    width: 30px;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.03em;
    font-size: 0.6rem;
  }

  @media (max-width: 1280px) {
    .right-sidebar {
      display: none;
    }
  }
</style>

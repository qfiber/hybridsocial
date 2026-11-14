<script lang="ts">
  import { page } from '$app/state';
  import { api } from '$lib/api/client.js';
  import { hasPermission, hasAnyPermission } from '$lib/stores/auth.js';
  import { sudoExpiresAt, isSudoValid } from '$lib/stores/admin-sudo.js';
  import {
    adminSections,
    adminItemForPath,
    type AdminItem,
    type AdminSection,
    type AdminCluster,
  } from '$lib/admin-nav.js';
  import BrandMark from '$lib/components/ui/BrandMark.svelte';
  import { instanceName } from '$lib/stores/instance.js';
  import { themeStore, resolvedMode } from '$lib/stores/theme.js';
  import { t } from '$lib/stores/i18n.js';

  // `open` only matters below the drawer breakpoint, where the rail is an
  // off-canvas drawer the top bar's menu button opens.
  // Same rule as the app header: an uploaded logo is usually a wordmark that
  // already carries the name, so it stands alone at full width. Without one,
  // show the initial mark next to the instance name.
  let logo = $derived(
    $resolvedMode === 'dark'
      ? $themeStore?.dark_logo_url || $themeStore?.logo_url
      : $themeStore?.logo_url || $themeStore?.dark_logo_url,
  );

  let { open = false, onclose }: { open?: boolean; onclose?: () => void } = $props();

  function itemVisible(item: AdminItem): boolean {
    if (item.hidden) return false;
    if (item.permission) return hasPermission(item.permission);
    if (item.anyPermission) return hasAnyPermission(...item.anyPermission);
    return true;
  }

  // Filter down to sections the current staffer can actually reach, and
  // drop any section left with no items. Recomputed reactively so a
  // permission change (rare, but possible mid-session) reflows the rail.
  let sections = $derived(
    adminSections
      .map((s) => ({ ...s, items: s.items.filter(itemVisible) }))
      .filter((s) => s.items.length > 0),
  );

  // Two halves: what staff act on daily, then what they configure.
  const clusters: { id: AdminCluster; labelKey: string }[] = [
    { id: 'operate', labelKey: 'admin_shell.cluster_operate' },
    { id: 'configure', labelKey: 'admin_shell.cluster_configure' },
  ];

  // Live pending counts, shown as red pills next to Approvals / Appeals —
  // the same urgency cue the dashboard uses, so staff feel the queue
  // without opening it. Moved here from the old user-management tab bar.
  let pendingApprovals = $state(0);
  let pendingAppeals = $state(0);
  let sudoOk = $derived(isSudoValid($sudoExpiresAt));

  async function loadCounts() {
    const [a, ap] = await Promise.all([
      api
        .poll<{ data: { id: string }[] }>('/api/v1/admin/pending_accounts')
        .then((r) => (r.data || []).length)
        .catch(() => 0),
      api
        .poll<{ data: { id: string }[] }>('/api/v1/admin/appeals', { status: 'pending' })
        .then((r) => (r.data || []).length)
        .catch(() => 0),
    ]);
    pendingApprovals = a;
    pendingAppeals = ap;
  }

  // Both endpoints are sudo-gated and the sidebar renders outside the sudo
  // gate, so only poll while unlocked. Polling while locked just 403s, and
  // each 403 re-fires admin-sudo-required.
  $effect(() => {
    if (!sudoOk) return;
    loadCounts();
    const timer = setInterval(loadCounts, 60_000);
    return () => clearInterval(timer);
  });

  function badgeCount(item: AdminItem): number {
    if (item.badge === 'approvals') return pendingApprovals;
    if (item.badge === 'appeals') return pendingAppeals;
    return 0;
  }

  // A dedicated editor (hidden item) highlights the settings page it belongs to.
  let currentParent = $derived(adminItemForPath(page.url.pathname)?.parent ?? null);

  function isActive(href: string): boolean {
    if (href === '/admin') return page.url.pathname === '/admin';
    if (currentParent === href) return true;
    return page.url.pathname === href || page.url.pathname.startsWith(href + '/');
  }

  // A section is "current" when one of its items is active — used to tint
  // the section label so you can see where you are at a glance.
  function sectionActive(section: AdminSection): boolean {
    return section.items.some((i) => isActive(i.href));
  }
</script>

{#if open}
  <button
    type="button"
    class="admin-sidebar-backdrop"
    aria-label={$t('admin_shell.close_menu')}
    onclick={() => onclose?.()}
  ></button>
{/if}

<aside class="admin-sidebar" class:open id="admin-sidebar">
  <div class="admin-sidebar-header">
    <a href="/admin" class="admin-brand" class:has-logo={!!logo} aria-label="{$instanceName} {$t('admin_shell.admin')}">
      {#if logo}
        <img src={logo} alt="" class="admin-brand-logo" />
        <span class="admin-brand-sub">{$t('admin_shell.admin')}</span>
      {:else}
        <span class="admin-brand-mark"><BrandMark size={28} /></span>
        <span class="admin-brand-text">
          <span class="admin-brand-name">{$instanceName}</span>
          <span class="admin-brand-sub">{$t('admin_shell.admin')}</span>
        </span>
      {/if}
    </a>
  </div>

  <nav class="admin-nav" aria-label={$t('admin_shell.nav_label')}>
    {#each clusters as cluster (cluster.id)}
      {@const clusterSections = sections.filter((s) => s.cluster === cluster.id)}
      {#if clusterSections.length > 0}
        <div class="admin-nav-cluster">
          <p class="admin-nav-cluster-title">{$t(cluster.labelKey)}</p>
          {#each clusterSections as section (section.title)}
            <div class="admin-nav-group">
              <p class="admin-nav-group-title" class:current={sectionActive(section)}>{section.title}</p>
              <ul class="admin-nav-list">
                {#each section.items as item (item.href)}
                  {@const count = badgeCount(item)}
                  <li>
                    <a
                      href={item.href}
                      class="admin-nav-item"
                      class:active={isActive(item.href)}
                      aria-current={isActive(item.href) ? 'page' : undefined}
                    >
                      <svg class="admin-nav-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                        <path d={item.icon} />
                      </svg>
                      <span class="admin-nav-label">{item.label}</span>
                      {#if count > 0}
                        <span class="admin-nav-badge" title={$t('admin_shell.pending', { count })}>{count}</span>
                      {/if}
                    </a>
                  </li>
                {/each}
              </ul>
            </div>
          {/each}
        </div>
      {/if}
    {/each}
  </nav>

  <div class="admin-sidebar-footer">
    <a href="/home" class="admin-nav-item back-link">
      <svg class="admin-nav-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M10 19l-7-7m0 0l7-7m-7 7h18" />
      </svg>
      <span>{$t('admin_shell.back_to_app')}</span>
    </a>
  </div>
</aside>

<style>
  .admin-sidebar {
    position: sticky;
    top: 0;
    height: 100vh;
    height: 100dvh;
    width: 248px;
    display: flex;
    flex-direction: column;
    background: var(--color-surface-raised);
    border-inline-end: 1px solid var(--color-border);
    overflow-y: auto;
    flex-shrink: 0;
  }

  .admin-sidebar-header {
    padding: var(--space-4);
    border-block-end: 1px solid var(--color-border);
  }

  .admin-brand {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    min-width: 0;
    color: var(--color-text);
    text-decoration: none;
  }

  .admin-brand:hover {
    text-decoration: none;
  }

  /* Logo on its own row, the "Admin" label under it. */
  .admin-brand.has-logo {
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
  }

  .admin-brand-logo {
    display: block;
    height: 32px;
    width: auto;
    max-width: 100%;
    object-fit: contain;
    object-position: left center;
  }

  :global([dir='rtl']) .admin-brand-logo {
    object-position: right center;
  }

  .admin-brand-mark {
    display: flex;
    flex-shrink: 0;
    max-width: 96px;
  }

  .admin-brand-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    line-height: 1.2;
  }

  .admin-brand-name {
    font-weight: 700;
    font-size: var(--text-sm);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .admin-brand-sub {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-primary);
  }

  .admin-nav {
    flex: 1;
    padding: var(--space-3) var(--space-2);
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .admin-nav-cluster {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .admin-nav-cluster + .admin-nav-cluster {
    padding-block-start: var(--space-4);
    border-block-start: 1px solid var(--color-border);
  }

  .admin-nav-cluster-title {
    margin: 0;
    padding-inline: var(--space-3);
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--color-text);
  }

  .admin-nav-group {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .admin-nav-group-title {
    margin: 0 0 4px;
    padding-inline: var(--space-3);
    font-size: 0.6875rem;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--color-text-tertiary);
  }

  .admin-nav-group-title.current {
    color: var(--color-primary);
  }

  .admin-nav-list {
    display: flex;
    flex-direction: column;
    gap: 2px;
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .admin-nav-item {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    color: var(--color-text-secondary);
    text-decoration: none;
    font-size: var(--text-sm);
    font-weight: 500;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .admin-nav-item:hover {
    background: var(--color-surface);
    color: var(--color-text);
    text-decoration: none;
  }

  .admin-nav-item.active {
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-weight: 600;
  }

  .admin-nav-icon {
    flex-shrink: 0;
  }

  .admin-nav-label {
    flex: 1;
    min-width: 0;
  }

  .admin-nav-badge {
    flex-shrink: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 20px;
    height: 20px;
    padding: 0 6px;
    border-radius: 9999px;
    background: var(--color-danger);
    color: var(--color-text-on-primary);
    font-size: 0.7rem;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }

  .admin-sidebar-footer {
    padding: var(--space-2);
    border-block-start: 1px solid var(--color-border);
    margin-block-start: auto;
  }

  .back-link {
    color: var(--color-text-tertiary);
  }

  .back-link:hover {
    color: var(--color-text);
  }

  .admin-sidebar-backdrop {
    display: none;
  }

  /* Below this width the rail becomes a drawer opened from the top bar. */
  @media (max-width: 900px) {
    .admin-sidebar {
      position: fixed;
      inset-block: 0;
      inset-inline-start: 0;
      z-index: var(--z-modal);
      box-shadow: var(--shadow-xl);
      transform: translateX(-100%);
      visibility: hidden;
      transition: transform var(--transition-base), visibility var(--transition-base);
    }

    :global([dir='rtl']) .admin-sidebar {
      transform: translateX(100%);
    }

    .admin-sidebar.open,
    :global([dir='rtl']) .admin-sidebar.open {
      transform: none;
      visibility: visible;
    }

    .admin-sidebar-backdrop {
      display: block;
      position: fixed;
      inset: 0;
      z-index: var(--z-modal-backdrop);
      border: 0;
      padding: 0;
      background: var(--color-overlay);
      cursor: pointer;
    }
  }

  /* Finger-sized targets on touch screens, whatever the width. */
  @media (pointer: coarse) {
    .admin-nav-item {
      min-height: 44px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .admin-sidebar {
      transition: none;
    }
  }
</style>

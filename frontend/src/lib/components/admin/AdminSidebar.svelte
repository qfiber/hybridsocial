<script lang="ts">
  import { page } from '$app/state';
  import { api } from '$lib/api/client.js';
  import { hasPermission, hasAnyPermission } from '$lib/stores/auth.js';
  import { sudoExpiresAt, isSudoValid } from '$lib/stores/admin-sudo.js';
  import { adminSections, type AdminItem, type AdminSection } from '$lib/admin-nav.js';

  function itemVisible(item: AdminItem): boolean {
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

  function isActive(href: string): boolean {
    if (href === '/admin') return page.url.pathname === '/admin';
    return page.url.pathname === href || page.url.pathname.startsWith(href + '/');
  }

  // A section is "current" when one of its items is active — used to tint
  // the section label so you can see where you are at a glance.
  function sectionActive(section: AdminSection): boolean {
    return section.items.some((i) => isActive(i.href));
  }
</script>

<aside class="admin-sidebar">
  <div class="admin-sidebar-header">
    <a href="/admin" class="admin-brand">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
      </svg>
      <span>Admin Panel</span>
    </a>
  </div>

  <nav class="admin-nav" aria-label="Admin navigation">
    {#each sections as section (section.title)}
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
                  <span class="admin-nav-badge" title="{count} pending">{count}</span>
                {/if}
              </a>
            </li>
          {/each}
        </ul>
      </div>
    {/each}
  </nav>

  <div class="admin-sidebar-footer">
    <a href="/home" class="admin-nav-item back-link">
      <svg class="admin-nav-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M10 19l-7-7m0 0l7-7m-7 7h18" />
      </svg>
      <span>Back to App</span>
    </a>
  </div>
</aside>

<style>
  .admin-sidebar {
    position: sticky;
    top: 0;
    height: 100vh;
    width: 240px;
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
    gap: var(--space-2);
    font-weight: 700;
    font-size: var(--text-base);
    color: var(--color-text);
    text-decoration: none;
  }

  .admin-brand:hover {
    text-decoration: none;
    color: var(--color-primary);
  }

  .admin-nav {
    flex: 1;
    padding: var(--space-3) var(--space-2);
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
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
    background: var(--color-danger, #dc2626);
    color: #fff;
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

  @media (max-width: 768px) {
    .admin-sidebar {
      position: fixed;
      z-index: var(--z-sticky);
      transform: translateX(-100%);
      transition: transform var(--transition-base);
    }
  }
</style>

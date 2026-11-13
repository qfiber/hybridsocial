<script lang="ts">
  // The admin shell's top bar: the drawer button (narrow screens), a
  // breadcrumb resolved from the nav catalog, and the sudo window countdown so
  // staff can see when they'll be asked to re-authenticate.
  import { page } from '$app/state';
  import { adminItemForPath, adminSectionForItem } from '$lib/admin-nav.js';
  import { sudoExpiresAt } from '$lib/stores/admin-sudo.js';
  import { t } from '$lib/stores/i18n.js';

  let { menuOpen = false, onmenu }: { menuOpen?: boolean; onmenu?: () => void } = $props();

  let item = $derived(adminItemForPath(page.url.pathname));
  let section = $derived(item ? adminSectionForItem(item) : null);
  // A sub-page (a report, a user) sits below its item in the trail.
  let isSubPage = $derived(!!item && page.url.pathname !== item.href);

  let now = $state(Date.now());
  $effect(() => {
    const timer = setInterval(() => (now = Date.now()), 15_000);
    return () => clearInterval(timer);
  });

  let minutesLeft = $derived.by(() => {
    if (!$sudoExpiresAt) return null;
    const ms = new Date($sudoExpiresAt).getTime() - now;
    return ms > 0 ? Math.max(1, Math.ceil(ms / 60_000)) : null;
  });
</script>

<header class="admin-topbar">
  <button
    type="button"
    class="admin-topbar-menu"
    aria-label={$t('admin_shell.open_menu')}
    aria-controls="admin-sidebar"
    aria-expanded={menuOpen}
    onclick={() => onmenu?.()}
  >
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
      <path d="M4 6h16M4 12h16M4 18h16" />
    </svg>
  </button>

  <nav class="admin-breadcrumb" aria-label={$t('admin_shell.breadcrumb')}>
    <ol>
      {#if section}
        <li>{section.title}</li>
      {/if}
      {#if item}
        <li>
          {#if isSubPage}
            <a href={item.href}>{item.label}</a>
          {:else}
            <span aria-current="page">{item.label}</span>
          {/if}
        </li>
      {/if}
      {#if isSubPage}
        <li><span aria-current="page">{$t('admin_shell.details')}</span></li>
      {/if}
    </ol>
  </nav>

  {#if minutesLeft !== null}
    <span
      class="admin-sudo-chip"
      class:expiring={minutesLeft <= 2}
      title={$t('admin_shell.sudo_hint')}
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <rect x="3" y="11" width="18" height="11" rx="2" />
        <path d="M7 11V7a5 5 0 0 1 9.9-1" />
      </svg>
      {$t('admin_shell.sudo_minutes', { count: minutesLeft })}
    </span>
  {/if}
</header>

<style>
  .admin-topbar {
    position: sticky;
    top: 0;
    z-index: var(--z-sticky);
    display: flex;
    align-items: center;
    gap: var(--space-3);
    min-height: 56px;
    padding: var(--space-2) var(--space-8);
    background: color-mix(in srgb, var(--color-bg) 88%, transparent);
    backdrop-filter: blur(8px);
    border-block-end: 1px solid var(--color-border);
  }

  .admin-topbar-menu {
    display: none;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    margin-inline-start: calc(-1 * var(--space-2));
    border: 0;
    border-radius: var(--radius-md);
    background: transparent;
    color: var(--color-text);
    cursor: pointer;
  }

  .admin-topbar-menu:hover {
    background: var(--color-surface-hover);
  }

  .admin-breadcrumb {
    flex: 1;
    min-width: 0;
  }

  .admin-breadcrumb ol {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin: 0;
    padding: 0;
    list-style: none;
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    white-space: nowrap;
    overflow: hidden;
  }

  .admin-breadcrumb li {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    min-width: 0;
  }

  .admin-breadcrumb li + li::before {
    content: '/';
    color: var(--color-text-tertiary);
  }

  .admin-breadcrumb a {
    color: var(--color-text-secondary);
    text-decoration: none;
  }

  .admin-breadcrumb a:hover {
    color: var(--color-primary);
  }

  .admin-breadcrumb [aria-current='page'] {
    color: var(--color-text);
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .admin-sudo-chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    flex-shrink: 0;
    padding: 4px 10px;
    border-radius: var(--radius-full);
    background: var(--color-surface-container);
    color: var(--color-text-secondary);
    font-size: var(--text-xs);
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .admin-sudo-chip.expiring {
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
  }

  @media (max-width: 1024px) {
    .admin-topbar {
      padding-inline: var(--space-4);
    }
  }

  @media (max-width: 900px) {
    .admin-topbar-menu {
      display: inline-flex;
    }

  }
</style>

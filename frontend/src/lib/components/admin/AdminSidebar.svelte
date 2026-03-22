<script lang="ts">
  import { page } from '$app/state';
  import { hasPermission, hasAnyPermission } from '$lib/stores/auth.js';

  interface AdminNavItem {
    href: string;
    label: string;
    icon: string;
    permission?: string;
    anyPermission?: string[];
  }

  const allNavItems: AdminNavItem[] = [
    { href: '/admin', label: 'Dashboard', icon: 'M4 5a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1V5zm10 0a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 15a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1v-4zm10 0a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z' },
    { href: '/admin/users', label: 'Users', icon: 'M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z', permission: 'users.view' },
    { href: '/admin/moderation', label: 'Moderation', icon: 'M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z', permission: 'reports.view' },
    { href: '/admin/federation', label: 'Federation', icon: 'M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z', anyPermission: ['federation.view', 'federation.manage'] },
    { href: '/admin/settings', label: 'Settings', icon: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z M15 12a3 3 0 11-6 0 3 3 0 016 0z', permission: 'settings.view' },
    { href: '/admin/theme', label: 'Theme', icon: 'M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01', permission: 'theme.manage' },
    { href: '/admin/email', label: 'Email', icon: 'M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z', permission: 'email.manage' },
    { href: '/admin/backups', label: 'Backups', icon: 'M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4', permission: 'backups.view' },
    { href: '/admin/relays', label: 'Relays', icon: 'M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z', permission: 'federation.relay_manage' },
    { href: '/admin/announcements', label: 'Announcements', icon: 'M11 5.882V19.24a1.76 1.76 0 01-3.417.592l-2.147-6.15M18 13a3 3 0 100-6M5.436 13.683A4.001 4.001 0 017 6h1.832c4.1 0 7.625-1.234 9.168-3v14c-1.543-1.766-5.067-3-9.168-3H7a3.988 3.988 0 01-1.564-.317z', permission: 'announcements.manage' },
    { href: '/admin/audit-log', label: 'Audit Log', icon: 'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01', permission: 'audit_log.view' },
    { href: '/admin/roles', label: 'Roles', icon: 'M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z', permission: 'roles.view' },
  ];

  function isVisible(item: AdminNavItem): boolean {
    if (!item.permission && !item.anyPermission) return true;
    if (item.permission) return hasPermission(item.permission);
    if (item.anyPermission) return hasAnyPermission(...item.anyPermission);
    return true;
  }

  let navItems = $derived(allNavItems.filter(isVisible));

  function isActive(href: string): boolean {
    if (href === '/admin') {
      return page.url.pathname === '/admin';
    }
    return page.url.pathname === href || page.url.pathname.startsWith(href + '/');
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
    <ul class="admin-nav-list">
      {#each navItems as item (item.href)}
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
            <span>{item.label}</span>
          </a>
        </li>
      {/each}
    </ul>
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
    padding: var(--space-4) var(--space-4);
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
    padding: var(--space-2);
  }

  .admin-nav-list {
    display: flex;
    flex-direction: column;
    gap: 2px;
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

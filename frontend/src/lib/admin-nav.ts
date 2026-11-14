// Single source of truth for the admin panel catalog. Consumed by the
// admin card hub (the /admin landing) and the grouped sidebar rail so the
// two never drift — the admin-side mirror of src/lib/settings-nav.ts.
//
// Grouping rationale: the Operate cluster is what staff act on day to day;
// Configure is what they set up and rarely touch. Every instance setting
// lives on exactly one Settings page (/admin/settings/<group>), rendered from
// the backend registry. Dedicated editors keep their URLs as hidden items.

export interface AdminItem {
  href: string;
  label: string;
  description: string;
  /** SVG path data for a 24x24 stroked icon. */
  icon: string;
  /** Gate: single required permission. */
  permission?: string;
  /** Gate: visible if the user holds ANY of these permissions. */
  anyPermission?: string[];
  /** Live count pill driver, resolved by the sidebar. */
  badge?: 'approvals' | 'appeals';
  /** Routable but not listed in the rail or the hub. */
  hidden?: boolean;
  /** For a hidden item: the listed item to highlight while it's open. */
  parent?: string;
}

export type AdminCluster = 'operate' | 'configure';

export interface AdminSection {
  title: string;
  /** Which half of the rail it sits in: daily work, or configuration. */
  cluster: AdminCluster;
  /** One-line description shown under the section on the card hub. */
  blurb: string;
  /** SVG path data for the section's 24x24 stroked icon. */
  icon: string;
  items: AdminItem[];
}

export const adminSections: AdminSection[] = [
  {
    title: 'Overview',
    cluster: 'operate',
    blurb: 'Health and activity at a glance',
    icon: 'M3 3h7v7H3zM14 3h7v7h-7zM14 14h7v7h-7zM3 14h7v7H3z',
    items: [
      { href: '/admin', label: 'Dashboard', description: 'Key counts and quick actions', icon: 'M3 3h7v7H3zM14 3h7v7h-7zM14 14h7v7h-7zM3 14h7v7H3z' },
      { href: '/admin/analytics', label: 'Analytics', description: 'Usage trends over time', icon: 'M3 3v18h18M8 17V9M13 17V5M18 17v-6', permission: 'settings.view' },
    ],
  },
  {
    title: 'Moderation',
    cluster: 'operate',
    blurb: 'The daily action queue',
    icon: 'M12 3l8 4v5c0 4.5-3.4 7.9-8 9-4.6-1.1-8-4.5-8-9V7zM9.5 12l1.8 1.8 3.5-3.6',
    items: [
      { href: '/admin/moderation', label: 'Reports & queue', description: 'Reports, verifications and auto-flagged posts', icon: 'M12 3l8 4v5c0 4.5-3.4 7.9-8 9-4.6-1.1-8-4.5-8-9V7zM9.5 12l1.8 1.8 3.5-3.6', permission: 'reports.view' },
      { href: '/admin/moderation/blocklists', label: 'Blocklists', description: 'Content filters, IPs, email domains, media hashes, hashtags', icon: 'M12 3l8 4v5c0 4.5-3.4 7.9-8 9-4.6-1.1-8-4.5-8-9V7zM9 9l6 6M15 9l-6 6', permission: 'reports.view' },
      { href: '/admin/user-management/appeals', label: 'Appeals', description: 'Suspended members asking for review', icon: 'M3 6l3 1m0 0l-3 9a5 5 0 006 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5 5 0 006 0M18 7l3 9m-9-14v18', permission: 'users.view', badge: 'appeals' },
      { href: '/admin/moderation/takedowns', label: 'Takedowns', description: 'Restore removed groups and pages, and control auto-deletion', icon: 'M12 3l8 4v5c0 4.5-3.4 7.9-8 9-4.6-1.1-8-4.5-8-9V7zM9 12l2 2 4-4', permission: 'reports.view' },
    ],
  },
  {
    title: 'People',
    cluster: 'operate',
    blurb: 'Accounts and who can do what',
    icon: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8',
    items: [
      { href: '/admin/user-management/users', label: 'Users', description: 'Search, suspend, roles, trust, verify', icon: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8', permission: 'users.view' },
      { href: '/admin/user-management/approvals', label: 'Approvals', description: 'Pending sign-ups awaiting review', icon: 'M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M8.5 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM17 11l2 2 4-4', permission: 'users.view', badge: 'approvals' },
      { href: '/admin/user-management/roles', label: 'Roles & permissions', description: 'Staff roles and what they can access', icon: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10zM9 12l2 2 4-4', permission: 'users.view' },
    ],
  },
  {
    title: 'Federation',
    cluster: 'operate',
    blurb: 'How this server talks to the fediverse',
    icon: 'M3.05 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.95M8 3.94V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.06M15 20.49V18a2 2 0 012-2h3.06M21 12a9 9 0 11-18 0 9 9 0 0118 0z',
    items: [
      { href: '/admin/federation', label: 'Instances & delivery', description: 'Known instances, policies, delivery queue, relays', icon: 'M3.05 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.95M8 3.94V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.06M15 20.49V18a2 2 0 012-2h3.06M21 12a9 9 0 11-18 0 9 9 0 0118 0z', anyPermission: ['federation.view', 'federation.manage'] },
    ],
  },
  {
    title: 'Content',
    cluster: 'configure',
    blurb: 'What members see and use',
    icon: 'M12 21a9 9 0 100-18 9 9 0 000 18zM8.5 14.5a4 4 0 007 0M9 9.5h.01M15 9.5h.01',
    items: [
      { href: '/admin/rules', label: 'Rules', description: 'The instance rules members agree to', icon: 'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4', permission: 'settings.manage' },
      { href: '/admin/site-pages', label: 'Site pages', description: 'Privacy, terms, and about pages', icon: 'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.59a1 1 0 01.7.29l5.42 5.42a1 1 0 01.29.7V19a2 2 0 01-2 2z', permission: 'settings.view' },
      { href: '/admin/announcements', label: 'Announcements', description: 'Banners shown to everyone on the server', icon: 'M11 5.88V19.24a1.76 1.76 0 01-3.42.59l-2.15-6.15M18 13a3 3 0 100-6M5.44 13.68A4 4 0 017 6h1.83c4.1 0 7.63-1.23 9.17-3v14c-1.54-1.77-5.07-3-9.17-3H7a4 4 0 01-1.56-.32z', permission: 'announcements.manage' },
      { href: '/admin/custom-emojis', label: 'Custom emojis', description: 'Instance emoji available in posts', icon: 'M12 21a9 9 0 100-18 9 9 0 000 18zM8.5 14.5a4 4 0 007 0M9 9.5h.01M15 9.5h.01', permission: 'settings.manage' },
      { href: '/admin/user-management/premium-reactions', label: 'Premium reactions', description: 'Reactions unlocked for paid tiers', icon: 'M12 21s-7-4.53-9.5-9A5.5 5.5 0 0112 6a5.5 5.5 0 019.5 6c-2.5 4.47-9.5 9-9.5 9z', permission: 'users.view' },
      { href: '/admin/user-management/badges', label: 'Profile badges', description: 'Badges you can grant to accounts', icon: 'M12 15a5 5 0 100-10 5 5 0 000 10zM8.2 13.5L7 22l5-3 5 3-1.2-8.5', permission: 'users.view' },
    ],
  },
  {
    title: 'Settings',
    cluster: 'configure',
    blurb: 'Every instance setting, one page per area',
    icon: 'M12 15a3 3 0 100-6 3 3 0 000 6zM19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 11-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 11-2.83-2.83l.06-.06A1.65 1.65 0 004.6 15a1.65 1.65 0 00-1.51-1H3a2 2 0 110-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06A1.65 1.65 0 009 4.6a1.65 1.65 0 001-1.51V3a2 2 0 114 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 110 4h-.09a1.65 1.65 0 00-1.51 1z',
    items: [
      { href: '/admin/settings/general', label: 'General', description: 'Name, description, contact and links', icon: 'M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6', permission: 'settings.manage' },
      { href: '/admin/settings/branding', label: 'Branding & theme', description: 'Theme editor, app links, email logo', icon: 'M12 3a9 9 0 100 18 1.5 1.5 0 001.06-2.56A1.5 1.5 0 0114.5 16H16a5 5 0 005-5c0-4.42-4.03-8-9-8zM6.5 12a1 1 0 100-2 1 1 0 000 2zM9.5 8a1 1 0 100-2 1 1 0 000 2zM14.5 8a1 1 0 100-2 1 1 0 000 2z', permission: 'theme.manage' },
      { href: '/admin/settings/access', label: 'Sign-up & access', description: 'Registration mode, captcha, who can see what', icon: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM19 8v6M22 11h-6', permission: 'settings.access' },
      { href: '/admin/settings/posting', label: 'Posting & accounts', description: 'Post, poll, profile and DM limits, trust gates', icon: 'M12 20h9M16.5 3.5a2.12 2.12 0 013 3L7 19l-4 1 1-4z', permission: 'settings.posting' },
      { href: '/admin/settings/media', label: 'Media & storage', description: 'Upload sizes, storage, media proxy, antivirus', icon: 'M4 16l4.59-4.59a2 2 0 012.82 0L16 16m-2-2l1.59-1.59a2 2 0 012.82 0L20 14M14 8h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z', permission: 'settings.media' },
      { href: '/admin/settings/discovery', label: 'Feeds & discovery', description: 'Timelines, trending, Explore, search', icon: 'M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z', permission: 'settings.discovery' },
      { href: '/admin/settings/federation', label: 'Federation', description: 'Delivery, dead actors, keyword filters', icon: 'M3.05 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.95M8 3.94V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.06M15 20.49V18a2 2 0 012-2h3.06M21 12a9 9 0 11-18 0 9 9 0 0118 0z', permission: 'federation.manage' },
      { href: '/admin/settings/moderation', label: 'Moderation & safety', description: 'Report emails, escalation, content filter, takedowns', icon: 'M12 3l8 4v5c0 4.5-3.4 7.9-8 9-4.6-1.1-8-4.5-8-9V7z', permission: 'settings.moderation' },
      { href: '/admin/settings/rate-limits', label: 'Rate limits', description: 'API and sign-in request limits', icon: 'M13 10V3L4 14h7v7l9-11h-7z', permission: 'settings.rate_limits' },
      { href: '/admin/settings/monetization', label: 'Monetization', description: 'Tiers, prices, payment gateway', icon: 'M12 1v22M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6', permission: 'settings.monetization' },
      { href: '/admin/settings/integrations', label: 'Integrations', description: 'Email, translation, webhooks, SMS, analytics', icon: 'M13.83 10.17a4 4 0 00-5.66 0l-4 4a4 4 0 105.66 5.66l1.1-1.1m-.76-4.9a4 4 0 005.66 0l4-4a4 4 0 00-5.66-5.66l-1.1 1.1', permission: 'settings.integrations' },
      { href: '/admin/settings/retention', label: 'Data retention', description: 'How long records are kept', icon: 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z', permission: 'settings.retention' },
      // Dedicated editors: reachable from their settings page, kept out of
      // the rail, and highlight their parent group while open.
      { href: '/admin/theme', label: 'Theme editor', description: 'Colors, fonts, logos, favicon, dark mode', icon: 'M12 3a9 9 0 100 18 1.5 1.5 0 001.06-2.56A1.5 1.5 0 0114.5 16H16a5 5 0 005-5c0-4.42-4.03-8-9-8zM6.5 12a1 1 0 100-2 1 1 0 000 2zM9.5 8a1 1 0 100-2 1 1 0 000 2zM14.5 8a1 1 0 100-2 1 1 0 000 2z', permission: 'theme.manage', hidden: true, parent: '/admin/settings/branding' },
      { href: '/admin/user-management/registration', label: 'Invites', description: 'Invite codes and sign-up mode', icon: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM19 8v6M22 11h-6', permission: 'users.view', hidden: true, parent: '/admin/settings/access' },
      { href: '/admin/user-management/posting-limits', label: 'Posting limits', description: 'How fast accounts can post', icon: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM12 6v6l4 2', permission: 'settings.manage', hidden: true, parent: '/admin/settings/posting' },
      { href: '/admin/user-management/tiers', label: 'Verification tiers', description: 'Per-tier post and media limits', icon: 'M12 2l9 5-9 5-9-5 9-5zM3 12l9 5 9-5M3 17l9 5 9-5', permission: 'users.view', hidden: true, parent: '/admin/settings/monetization' },
      { href: '/admin/email', label: 'Email', description: 'Delivery server and message templates', icon: 'M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z', permission: 'email.manage', hidden: true, parent: '/admin/settings/integrations' },
      { href: '/admin/translation', label: 'Translation', description: 'Post translation backend', icon: 'M4 5h7M9 3v2c0 4.418-2.239 8-5 8M5 9c0 2.144 2.952 3.908 6.5 4M12 20l4-9 4 9M17.1 17h-2.2', permission: 'settings.manage', hidden: true, parent: '/admin/settings/integrations' },
      { href: '/admin/webhooks', label: 'Webhooks', description: 'Push events to external services', icon: 'M13.83 10.17a4 4 0 00-5.66 0l-4 4a4 4 0 105.66 5.66l1.1-1.1m-.76-4.9a4 4 0 005.66 0l4-4a4 4 0 00-5.66-5.66l-1.1 1.1', permission: 'settings.manage', hidden: true, parent: '/admin/settings/integrations' },
    ],
  },
  {
    title: 'Records',
    cluster: 'configure',
    blurb: 'Backups and the staff action log',
    icon: 'M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01',
    items: [
      { href: '/admin/backups', label: 'Backups', description: 'Encrypted database snapshots', icon: 'M4 7v10c0 2.21 3.58 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.58 4 8 4s8-1.79 8-4M4 7c0-2.21 3.58-4 8-4s8 1.79 8 4', permission: 'backups.view' },
      { href: '/admin/audit-log', label: 'Audit log', description: 'Every staff action, timestamped', icon: 'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01', permission: 'audit_log.view' },
    ],
  },
];

const byHref = new Map<string, AdminItem>();
for (const s of adminSections) for (const it of s.items) byHref.set(it.href, it);

/** The catalog item registered at exactly `href`, or null. */
export function adminItemByHref(href: string): AdminItem | null {
  return byHref.get(href) ?? null;
}

/** The section that owns an item, for the breadcrumb. */
export function adminSectionForItem(item: AdminItem): AdminSection | null {
  return adminSections.find((s) => s.items.includes(item)) ?? null;
}

/** Resolve the admin item for a pathname (longest-prefix match), or null. */
export function adminItemForPath(pathname: string): AdminItem | null {
  let best: AdminItem | null = null;
  for (const [href, item] of byHref) {
    // '/admin' is only itself; every other item may own sub-paths.
    const matches =
      href === '/admin'
        ? pathname === '/admin'
        : pathname === href || pathname.startsWith(href + '/');
    if (matches && (!best || href.length > best.href.length)) best = item;
  }
  return best;
}

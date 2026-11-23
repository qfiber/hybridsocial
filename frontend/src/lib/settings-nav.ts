// Single source of truth for the settings catalog. Consumed by the
// settings overview, the section sidebar and the layout's title lookup so
// they never drift. Labels are i18n keys; resolve them with $t.

export interface SettingsItem {
  href: string;
  /** i18n key of the section name. */
  labelKey: string;
  /** i18n key of the one-line summary. */
  descKey: string;
  /** SVG path data for a 24x24 stroked icon. */
  icon: string;
  /** Extra search terms: the options inside the section, so a search for
      "2FA" or "dark" finds the page that holds it. English; the translated
      label and summary are searched too. */
  keywords: string;
}

export interface SettingsGroup {
  /** i18n key of the group heading. */
  titleKey: string;
  items: SettingsItem[];
}

export const settingsGroups: SettingsGroup[] = [
  {
    titleKey: 'settings.group_you',
    items: [
      { href: '/settings/profile', labelKey: 'settings.nav_profile', descKey: 'settings.nav_profile_desc', icon: 'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M12 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8z', keywords: 'name display bio about avatar picture photo header banner fields links birthday location badge' },
      { href: '/settings/account', labelKey: 'settings.nav_account', descKey: 'settings.nav_account_desc', icon: 'M12 15v2m-6 4h12a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2zm10-10V7a4 4 0 0 0-8 0v4', keywords: 'email address language locale arabic english translation translate posting language post language verification verified delete close account' },
    ],
  },
  {
    titleKey: 'settings.group_preferences',
    items: [
      { href: '/settings/appearance', labelKey: 'settings.nav_appearance', descKey: 'settings.nav_appearance_desc', icon: 'M12 3a9 9 0 1 0 9 9 9 9 0 0 0-9-9zm0 0v18', keywords: 'theme dark light mode system colors feed home tab latest for you top replies threads threaded flat comments autoplay video gif data' },
      { href: '/settings/notifications', labelKey: 'settings.nav_notifications', descKey: 'settings.nav_notifications_desc', icon: 'M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 0 1-3.46 0', keywords: 'push email alerts sound follows mentions replies reactions boosts quotes polls invites' },
      { href: '/settings/privacy', labelKey: 'settings.nav_privacy', descKey: 'settings.nav_privacy_desc', icon: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z', keywords: 'lock private locked approve followers discoverable directory search engines indexing link previews unfurl follower counts messages dm direct group dm invites pages auto delete old posts default visibility remote media' },
      { href: '/settings/tags', labelKey: 'settings.nav_tags', descKey: 'settings.nav_tags_desc', icon: 'M4 9h16M4 15h16M10 3 8 21M16 3l-2 18', keywords: 'hashtags tags follow mute topics unfollow unmute' },
    ],
  },
  {
    titleKey: 'settings.group_safety',
    items: [
      { href: '/settings/blocks', labelKey: 'settings.nav_blocks', descKey: 'settings.nav_blocks_desc', icon: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM4.93 4.93l14.14 14.14', keywords: 'block mute domain servers instances unblock unmute' },
      { href: '/settings/filters', labelKey: 'settings.nav_filters', descKey: 'settings.nav_filters_desc', icon: 'M22 3H2l8 9.46V19l4 2v-8.54L22 3z', keywords: 'keywords words phrases hide warn spoilers' },
      { href: '/settings/follow-requests', labelKey: 'settings.nav_follow_requests', descKey: 'settings.nav_follow_requests_desc', icon: 'M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M8.5 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM17 11l2 2 4-4', keywords: 'approve decline pending followers' },
      { href: '/settings/moderation', labelKey: 'settings.nav_moderation', descKey: 'settings.nav_moderation_desc', icon: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10zM9 12l2 2 4-4', keywords: 'removed takedown appeal moderators' },
    ],
  },
  {
    titleKey: 'settings.group_security',
    items: [
      { href: '/settings/security', labelKey: 'settings.nav_security', descKey: 'settings.nav_security_desc', icon: 'M7 11V7a5 5 0 0 1 10 0v4M5 11h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z', keywords: 'password two factor 2fa otp authenticator security keys passkeys webauthn sessions devices sign out recovery code external links' },
    ],
  },
  {
    titleKey: 'settings.group_data',
    items: [
      { href: '/settings/history', labelKey: 'settings.nav_history', descKey: 'settings.nav_history_desc', icon: 'M3 3v5h5M3.05 13a9 9 0 1 0 .5-4m-.5 4h4m5-8v5l3 2', keywords: 'recently viewed seen posts clear' },
      { href: '/settings/import-export', labelKey: 'settings.nav_import_export', descKey: 'settings.nav_import_export_desc', icon: 'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3', keywords: 'export import backup download archive move migrate migration alias also known as' },
    ],
  },
  {
    titleKey: 'settings.group_more',
    items: [
      { href: '/settings/donations', labelKey: 'settings.nav_donations', descKey: 'settings.nav_donations_desc', icon: 'M12 2v20M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6', keywords: 'tips crypto wallet bitcoin ethereum' },
      { href: '/settings/developers', labelKey: 'settings.nav_developers', descKey: 'settings.nav_developers_desc', icon: 'M16 18l6-6-6-6M8 6l-6 6 6 6', keywords: 'api apps bots tokens webhooks applications' },
    ],
  },
];

const byHref = new Map<string, SettingsItem>();
for (const g of settingsGroups) for (const it of g.items) byHref.set(it.href, it);

/** Resolve the settings item for a pathname (longest prefix match), or null on the index. */
export function settingsItemForPath(pathname: string): SettingsItem | null {
  if (pathname === '/settings' || pathname === '/settings/') return null;
  let best: SettingsItem | null = null;
  for (const [href, item] of byHref) {
    if (pathname === href || pathname.startsWith(href + '/')) {
      if (!best || href.length > best.href.length) best = item;
    }
  }
  return best;
}

/** Groups narrowed to the items matching `query` (all words must match the
    translated label/summary or the keywords). Empty groups are dropped. */
export function filterSettings(
  query: string,
  translate: (key: string) => string,
): SettingsGroup[] {
  const words = query.toLocaleLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return settingsGroups;
  return settingsGroups
    .map((g) => ({
      ...g,
      items: g.items.filter((it) => {
        const hay = `${translate(it.labelKey)} ${translate(it.descKey)} ${it.keywords}`.toLocaleLowerCase();
        return words.every((w) => hay.includes(w));
      }),
    }))
    .filter((g) => g.items.length > 0);
}

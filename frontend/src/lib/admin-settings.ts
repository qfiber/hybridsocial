// Front-end metadata for the registry-driven settings pages: URL slugs and
// the dedicated editors each group links to. The settings themselves (types,
// sections, defaults, permissions) come from GET /api/v1/admin/settings/schema.

export interface RelatedPage {
  href: string;
  /** i18n keys. */
  titleKey: string;
  descriptionKey: string;
}

export const settingsGroupIds = [
  'general',
  'branding',
  'access',
  'posting',
  'media',
  'discovery',
  'federation',
  'moderation',
  'rate_limits',
  'monetization',
  'integrations',
  'retention',
] as const;

export type SettingsGroupId = (typeof settingsGroupIds)[number];

export function groupFromSlug(slug: string): SettingsGroupId | null {
  const id = slug.replaceAll('-', '_');
  return (settingsGroupIds as readonly string[]).includes(id) ? (id as SettingsGroupId) : null;
}

export function settingsHref(id: SettingsGroupId): string {
  return `/admin/settings/${id.replaceAll('_', '-')}`;
}

const related = (href: string, name: string): RelatedPage => ({
  href,
  titleKey: `admin_settings.related.${name}`,
  descriptionKey: `admin_settings.related.${name}_desc`,
});

/** Dedicated editors shown as cards at the top of a group's page. */
export const relatedPages: Partial<Record<SettingsGroupId, RelatedPage[]>> = {
  branding: [related('/admin/theme', 'theme')],
  access: [related('/admin/user-management/registration', 'invites')],
  posting: [related('/admin/user-management/posting-limits', 'posting_limits')],
  monetization: [related('/admin/user-management/tiers', 'tiers')],
  integrations: [
    related('/admin/email', 'email'),
    related('/admin/translation', 'translation'),
    related('/admin/webhooks', 'webhooks'),
  ],
};

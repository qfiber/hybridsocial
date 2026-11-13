import { redirect } from '@sveltejs/kit';

// General moved to the registry-driven settings pages.
export function load() {
  redirect(301, '/admin/settings/general');
}

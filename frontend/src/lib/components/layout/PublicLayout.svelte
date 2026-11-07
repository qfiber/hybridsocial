<script lang="ts">
  import type { Snippet } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { instanceName } from '$lib/stores/instance.js';
  import { t } from '$lib/stores/i18n.js';

  let { children }: { children: Snippet } = $props();

  let loginHref = $derived(`/login?next=${encodeURIComponent(page.url.pathname)}`);

  // Reacting, following and the like need an account. Send those clicks to login,
  // returning here afterwards, rather than letting them fail against the API.
  function requireLogin(e: MouseEvent) {
    const target = e.target as HTMLElement;
    if (!target.closest('[data-requires-login]')) return;
    if (!target.closest('button, a, [role="button"], input')) return;
    e.preventDefault();
    e.stopPropagation();
    goto(loginHref);
  }
</script>

<header class="public-header">
  <a class="public-brand" href={loginHref}>{$instanceName}</a>
  <nav class="public-nav" aria-label={$t('auth.login')}>
    <a class="public-link" href={loginHref}>{$t('auth.login')}</a>
    <a class="public-link public-link-primary" href="/register">{$t('auth.register')}</a>
  </nav>
</header>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<main class="public-main" onclickcapture={requireLogin}>
  {@render children()}
</main>

<style>
  .public-header {
    position: sticky;
    inset-block-start: 0;
    z-index: 30;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    min-height: var(--header-height, 60px);
    padding-inline: var(--space-4);
    background: var(--color-surface-base, #fff);
    border-block-end: 1px solid var(--color-border);
  }

  .public-brand {
    min-width: 0;
    overflow: hidden;
    font-weight: 700;
    color: var(--color-primary);
    text-decoration: none;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .public-nav {
    display: flex;
    flex-shrink: 0;
    align-items: center;
    gap: var(--space-2);
  }

  .public-link {
    display: inline-flex;
    align-items: center;
    min-height: 40px;
    padding-inline: var(--space-3);
    border-radius: var(--radius-full);
    color: var(--color-text);
    font-size: var(--text-sm);
    font-weight: 600;
    text-decoration: none;
  }

  .public-link-primary {
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
  }

  .public-main {
    width: 100%;
    max-width: var(--feed-max-width);
    margin-inline: auto;
    padding: var(--space-4);
  }
</style>

<script lang="ts">
  // The settings catalog as navigation. `compact` is the section sidebar
  // (icon + name, current one highlighted); `detailed` is the overview
  // (icon + name + summary, one card per group).
  import type { SettingsGroup } from '$lib/settings-nav.js';
  import { t } from '$lib/stores/i18n.js';

  let {
    groups,
    activeHref = '',
    variant = 'compact',
  }: {
    groups: SettingsGroup[];
    activeHref?: string;
    variant?: 'compact' | 'detailed';
  } = $props();
</script>

<nav class="settings-nav {variant}" aria-label={$t('settings.nav_label')}>
  {#each groups as group (group.titleKey)}
    <section class="nav-group">
      <h2 class="nav-group-title">{$t(group.titleKey)}</h2>
      <ul class="nav-list">
        {#each group.items as item (item.href)}
          {@const active = item.href === activeHref}
          <li>
            <a href={item.href} class="nav-item" class:active aria-current={active ? 'page' : undefined}>
              <span class="nav-icon">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d={item.icon} /></svg>
              </span>
              <span class="nav-text">
                <span class="nav-label">{$t(item.labelKey)}</span>
                {#if variant === 'detailed'}
                  <span class="nav-desc">{$t(item.descKey)}</span>
                {/if}
              </span>
              {#if variant === 'detailed'}
                <svg class="rtl-mirror nav-chevron" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="9 18 15 12 9 6" /></svg>
              {/if}
            </a>
          </li>
        {/each}
      </ul>
    </section>
  {/each}
</nav>

<style>
  .settings-nav {
    display: flex;
    flex-direction: column;
  }

  .nav-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
  }

  .nav-group-title {
    margin: 0;
    font-size: var(--text-xs);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--color-text-tertiary);
  }

  .nav-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    color: var(--color-text);
    text-decoration: none;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .nav-item:hover {
    text-decoration: none;
  }

  .nav-item:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: -2px;
  }

  .nav-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    border-radius: var(--radius-md);
    color: var(--color-primary);
    background: var(--color-primary-soft);
  }

  .nav-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }

  .nav-label {
    font-size: var(--text-sm);
    font-weight: 600;
  }

  .nav-desc {
    font-size: var(--text-xs);
    line-height: 1.4;
    color: var(--color-text-secondary);
  }

  .nav-chevron {
    flex-shrink: 0;
    color: var(--color-text-tertiary);
  }

  /* ---- Sidebar ---- */
  .compact {
    gap: var(--space-4);
  }

  .compact .nav-group-title {
    padding: 0 var(--space-3) var(--space-1);
  }

  .compact .nav-item {
    padding: 6px var(--space-3);
    border-radius: var(--radius-lg);
    color: var(--color-text-secondary);
  }

  .compact .nav-icon {
    width: 30px;
    height: 30px;
    background: transparent;
    color: var(--color-text-tertiary);
  }

  .compact .nav-item:hover {
    background: var(--color-surface-container-low);
    color: var(--color-text);
  }

  .compact .nav-item.active {
    background: var(--color-primary-soft);
    color: var(--color-primary);
  }

  .compact .nav-item.active .nav-icon {
    color: var(--color-primary);
  }

  /* ---- Overview: one grouped card per section group ---- */
  .detailed {
    gap: var(--space-5);
  }

  .detailed .nav-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .detailed .nav-group-title {
    padding-inline: var(--space-1);
  }

  .detailed .nav-list {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .detailed li + li {
    border-block-start: 1px solid var(--color-border);
  }

  .detailed .nav-item {
    padding: var(--space-3) var(--space-4);
    min-height: 60px;
  }

  .detailed .nav-icon {
    width: 38px;
    height: 38px;
  }

  .detailed .nav-item:hover {
    background: var(--color-surface-container-low);
  }

  .detailed .nav-item:hover .nav-chevron {
    color: var(--color-primary);
  }

  @container settings (min-width: 760px) {
    /* Wide overview: groups flow into two columns. */
    .detailed {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      align-items: start;
    }
  }
</style>

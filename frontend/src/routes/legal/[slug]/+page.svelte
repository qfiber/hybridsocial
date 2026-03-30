<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { getPublicSitePage } from '$lib/api/site-pages.js';
  import { getInstanceInfo } from '$lib/api/instance.js';
  import type { PublicSitePage } from '$lib/api/site-pages.js';
  import type { InstanceRule } from '$lib/api/types.js';

  let sitePage: PublicSitePage | null = $state(null);
  let rules: InstanceRule[] = $state([]);
  let loading = $state(true);
  let notFound = $state(false);

  let slug = $derived(page.params.slug);
  let isAbout = $derived(slug === 'about');

  onMount(async () => {
    try {
      const promises: Promise<unknown>[] = [getPublicSitePage(slug!)];
      if (slug === 'about') {
        promises.push(getInstanceInfo());
      }
      const results = await Promise.all(promises);
      sitePage = results[0] as PublicSitePage;
      if (slug === 'about' && results[1]) {
        rules = (results[1] as { rules: InstanceRule[] }).rules || [];
      }
    } catch {
      notFound = true;
    } finally {
      loading = false;
    }
  });
</script>

<svelte:head>
  <title>{sitePage?.title || 'Page'} - HybridSocial</title>
</svelte:head>

{#if loading}
  <div class="page-loading">Loading...</div>
{:else if notFound || !sitePage}
  <div class="page-not-found">
    <h1>Page not found</h1>
    <p>This page doesn't exist.</p>
    <a href="/">Back to home</a>
  </div>
{:else if !sitePage.body_html}
  <article class="site-page">
    <h1 class="site-page-title">{sitePage.title}</h1>
    <div class="page-placeholder">
      <p>This page hasn't been written yet. The server administrator will publish it soon.</p>
      <a href="/">Back to home</a>
    </div>
  </article>
{:else}
  <article class="site-page">
    <h1 class="site-page-title">{sitePage.title}</h1>
    {#if sitePage.updated_at}
      <p class="site-page-updated">
        Last updated: {new Date(sitePage.updated_at).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })}
      </p>
    {/if}
    <div class="site-page-body">
      {@html sitePage.body_html}
    </div>

    {#if isAbout && rules.length > 0}
      <section class="server-rules">
        <h2 class="rules-title">Server Rules</h2>
        <p class="rules-subtitle">By using this server, you agree to follow these rules.</p>
        <ol class="rules-list">
          {#each rules as rule, i (rule.id)}
            <li class="rules-item" style="animation-delay: {0.05 * i}s">
              <span class="rules-number">{i + 1}</span>
              <span class="rules-text">{rule.text}</span>
            </li>
          {/each}
        </ol>
      </section>
    {/if}
  </article>
{/if}

<style>
  .page-loading {
    text-align: center;
    padding: var(--space-16);
    color: var(--color-text-secondary);
  }

  .page-not-found {
    text-align: center;
    padding: var(--space-16);
  }

  .page-not-found h1 {
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .page-not-found p {
    color: var(--color-text-secondary);
    margin-block-end: var(--space-4);
  }

  .page-not-found a {
    color: var(--color-primary);
  }

  .page-placeholder {
    text-align: center;
    padding: var(--space-12) 0;
    color: var(--color-text-secondary);
  }

  .page-placeholder p {
    margin-block-end: var(--space-4);
  }

  .page-placeholder a {
    color: var(--color-primary);
  }

  .site-page-title {
    font-size: var(--text-3xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .site-page-updated {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    margin-block-end: var(--space-8);
    padding-block-end: var(--space-4);
    border-block-end: 1px solid var(--color-border);
  }

  .site-page-body {
    font-size: var(--text-base);
    line-height: 1.8;
    color: var(--color-text);
  }

  .site-page-body :global(h1) {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin: var(--space-8) 0 var(--space-3);
  }

  .site-page-body :global(h2) {
    font-size: var(--text-xl);
    font-weight: 600;
    margin: var(--space-6) 0 var(--space-3);
  }

  .site-page-body :global(h3) {
    font-size: var(--text-lg);
    font-weight: 600;
    margin: var(--space-5) 0 var(--space-2);
  }

  .site-page-body :global(p) {
    margin: var(--space-3) 0;
  }

  .site-page-body :global(ul),
  .site-page-body :global(ol) {
    margin: var(--space-3) 0;
    padding-inline-start: var(--space-6);
  }

  .site-page-body :global(li) {
    margin: var(--space-1) 0;
  }

  .site-page-body :global(a) {
    color: var(--color-primary);
  }

  .site-page-body :global(strong) {
    font-weight: 600;
  }

  .site-page-body :global(code) {
    background: var(--color-surface);
    padding: 2px 6px;
    border-radius: var(--radius-sm);
    font-size: 0.9em;
  }

  /* ---- Server rules ---- */
  .server-rules {
    margin-block-start: var(--space-8);
    padding-block-start: var(--space-6);
    border-block-start: 1px solid var(--color-border);
  }

  .rules-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-1);
  }

  .rules-subtitle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-5);
  }

  .rules-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .rules-item {
    display: flex;
    align-items: flex-start;
    gap: var(--space-4);
    padding: var(--space-4);
    background: var(--color-surface);
    border-radius: var(--radius-lg);
    animation: fadeUp 0.4s cubic-bezier(0.22, 1, 0.36, 1) both;
    transition: background 0.2s ease;
  }

  .rules-item:hover {
    background: var(--color-primary-soft);
  }

  .rules-number {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border-radius: var(--radius-full);
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    font-size: var(--text-xs);
    font-weight: 700;
    flex-shrink: 0;
  }

  .rules-text {
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: 1.6;
    padding-block-start: 3px;
  }

  /* ---- Entrance animations ---- */
  @keyframes fadeUp {
    from {
      opacity: 0;
      transform: translateY(14px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .site-page {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) both;
  }

  .site-page-title {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.05s both;
  }

  .site-page-updated {
    animation: fadeUp 0.4s cubic-bezier(0.22, 1, 0.36, 1) 0.1s both;
  }

  .site-page-body {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.15s both;
  }

  .page-not-found,
  .page-placeholder {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) both;
  }

  @media (prefers-reduced-motion: reduce) {
    .site-page,
    .site-page-title,
    .site-page-updated,
    .site-page-body,
    .page-not-found,
    .page-placeholder {
      animation: none !important;
    }
  }
</style>

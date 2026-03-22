<script lang="ts">
  import { onMount } from 'svelte';
  import { getInstanceInfo } from '$lib/api/instance.js';
  import type { InstanceInfo } from '$lib/api/types.js';

  let instance = $state<InstanceInfo | null>(null);
  let loading = $state(true);
  let error = $state('');

  onMount(async () => {
    try {
      instance = await getInstanceInfo();
    } catch {
      error = 'Failed to load instance information.';
    } finally {
      loading = false;
    }
  });
</script>

<svelte:head>
  <title>About - {instance?.title || 'HybridSocial'}</title>
</svelte:head>

<div class="about-page">
  {#if loading}
    <div class="about-loading">
      <div class="spinner"></div>
    </div>
  {:else if error}
    <div class="about-error">{error}</div>
  {:else if instance}
    <div class="about-card">
      <div class="about-hero">
        <h1 class="about-title">{instance.title}</h1>
        <p class="about-version">HybridSocial v{instance.version}</p>
      </div>

      {#if instance.description}
        <div class="about-section">
          <h2 class="section-label">About</h2>
          <p class="about-description">{instance.description}</p>
        </div>
      {/if}

      <div class="about-section">
        <h2 class="section-label">Statistics</h2>
        <div class="stats-grid">
          <div class="stat-item">
            <span class="stat-value">{instance.stats.user_count.toLocaleString()}</span>
            <span class="stat-name">Users</span>
          </div>
          <div class="stat-item">
            <span class="stat-value">{instance.stats.post_count.toLocaleString()}</span>
            <span class="stat-name">Posts</span>
          </div>
          <div class="stat-item">
            <span class="stat-value">{instance.stats.domain_count.toLocaleString()}</span>
            <span class="stat-name">Known instances</span>
          </div>
        </div>
      </div>

      <div class="about-section">
        <h2 class="section-label">Details</h2>
        <dl class="details-list">
          <div class="detail-row">
            <dt>Registration</dt>
            <dd>
              {#if instance.registrations_open}
                <span class="badge badge-open">Open</span>
              {:else}
                <span class="badge badge-closed">Closed</span>
              {/if}
            </dd>
          </div>

          {#if instance.contact_email}
            <div class="detail-row">
              <dt>Contact</dt>
              <dd><a href="mailto:{instance.contact_email}" class="contact-link">{instance.contact_email}</a></dd>
            </div>
          {/if}

          <div class="detail-row">
            <dt>Max post length</dt>
            <dd>{instance.max_post_length.toLocaleString()} characters</dd>
          </div>

          <div class="detail-row">
            <dt>Software</dt>
            <dd>HybridSocial v{instance.version}</dd>
          </div>
        </dl>
      </div>

      {#if instance.rules && instance.rules.length > 0}
        <div class="about-section">
          <h2 class="section-label">Rules</h2>
          <ol class="rules-list">
            {#each instance.rules as rule (rule.id)}
              <li class="rule-item">{rule.text}</li>
            {/each}
          </ol>
        </div>
      {/if}

      <div class="about-footer">
        <p class="footer-text">
          Powered by <strong>HybridSocial</strong> &mdash; Decentralized social networking built on ActivityPub.
        </p>
      </div>
    </div>
  {/if}
</div>

<style>
  .about-page {
    max-width: 640px;
    margin: 0 auto;
    padding: var(--space-6);
  }

  .about-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-12);
  }

  .spinner {
    width: 24px;
    height: 24px;
    border: 2px solid var(--color-border);
    border-top-color: var(--color-primary);
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .about-error {
    padding: var(--space-4);
    background: var(--color-danger-soft);
    color: var(--color-danger);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .about-card {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .about-hero {
    padding: var(--space-8) var(--space-6);
    background: linear-gradient(135deg, var(--color-primary), #0d9488);
    color: white;
    text-align: center;
  }

  .about-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-1);
  }

  .about-version {
    font-size: var(--text-sm);
    opacity: 0.8;
  }

  .about-section {
    padding: var(--space-5) var(--space-6);
    border-block-start: 1px solid var(--color-border);
  }

  .section-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    margin-block-end: var(--space-3);
  }

  .about-description {
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: 1.6;
  }

  .stats-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: var(--space-4);
  }

  .stat-item {
    text-align: center;
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .stat-value {
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--color-primary);
  }

  .stat-name {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .details-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .detail-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: var(--text-sm);
  }

  .detail-row dt {
    color: var(--color-text-secondary);
  }

  .detail-row dd {
    color: var(--color-text);
    font-weight: 500;
  }

  .badge {
    display: inline-block;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    font-size: var(--text-xs);
    font-weight: 600;
  }

  .badge-open {
    background: var(--color-success-soft);
    color: var(--color-success);
  }

  .badge-closed {
    background: var(--color-danger-soft);
    color: var(--color-danger);
  }

  .contact-link {
    color: var(--color-primary);
    text-decoration: none;
  }

  .contact-link:hover {
    text-decoration: underline;
  }

  .rules-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding-inline-start: var(--space-5);
  }

  .rule-item {
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: 1.5;
  }

  .about-footer {
    padding: var(--space-4) var(--space-6);
    border-block-start: 1px solid var(--color-border);
    text-align: center;
  }

  .footer-text {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  @media (max-width: 480px) {
    .stats-grid {
      grid-template-columns: 1fr;
      gap: var(--space-3);
    }
  }
</style>

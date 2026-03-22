<script lang="ts">
  import { page } from '$app/stores';

  let status = $state(404);
  let message = $state('Page not found');

  page.subscribe((p) => {
    status = p.status;
    message = p.error?.message || 'Something went wrong';
  });
</script>

<div class="error-page">
  <div class="error-content">
    <div class="error-code">{status}</div>
    <h1 class="error-title">{message}</h1>
    <p class="error-description">
      {#if status === 404}
        The page you're looking for doesn't exist or may have been moved.
      {:else if status === 500}
        Something went wrong on our end. Please try again later.
      {:else}
        An unexpected error occurred.
      {/if}
    </p>
    <a href="/home" class="error-home-btn">Go Home</a>
  </div>
</div>

<style>
  .error-page {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    padding: var(--space-6, 1.5rem);
    background: var(--color-bg, #f8fafc);
  }

  .error-content {
    text-align: center;
    max-width: 420px;
  }

  .error-code {
    font-size: 6rem;
    font-weight: 800;
    line-height: 1;
    color: var(--color-primary, #0d9488);
    margin-block-end: var(--space-2, 0.5rem);
  }

  .error-title {
    font-size: var(--text-xl, 1.25rem);
    font-weight: 700;
    color: var(--color-text, #0f172a);
    margin-block-end: var(--space-3, 0.75rem);
  }

  .error-description {
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text-secondary, #64748b);
    line-height: 1.6;
    margin-block-end: var(--space-6, 1.5rem);
  }

  .error-home-btn {
    display: inline-block;
    padding: var(--space-3, 0.75rem) var(--space-6, 1.5rem);
    background: var(--color-primary, #0d9488);
    color: var(--color-text-inverse, #fff);
    border-radius: var(--radius-full, 9999px);
    text-decoration: none;
    font-weight: 600;
    font-size: var(--text-sm, 0.875rem);
    transition: background-color 0.15s ease;
  }

  .error-home-btn:hover {
    background: var(--color-primary-hover, #0f766e);
    text-decoration: none;
  }
</style>

<div class="skeleton-post" aria-hidden="true">
  <div class="skeleton-header">
    <div class="skeleton-avatar skeleton-pulse"></div>
    <div class="skeleton-meta">
      <div class="skeleton-name skeleton-pulse"></div>
      <div class="skeleton-handle skeleton-pulse"></div>
    </div>
  </div>
  <div class="skeleton-body">
    <div class="skeleton-line skeleton-line-full skeleton-pulse"></div>
    <div class="skeleton-line skeleton-line-full skeleton-pulse"></div>
    <div class="skeleton-line skeleton-line-short skeleton-pulse"></div>
  </div>
  <div class="skeleton-actions">
    <div class="skeleton-action skeleton-pulse"></div>
    <div class="skeleton-action skeleton-pulse"></div>
    <div class="skeleton-action skeleton-pulse"></div>
  </div>
</div>

<style>
  .skeleton-post {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-4);
  }

  .skeleton-pulse {
    background: var(--color-bg-tertiary);
    border-radius: var(--radius-sm);
    animation: pulse 1.5s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 0.4; }
    50% { opacity: 0.7; }
  }

  .skeleton-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    margin-block-end: var(--space-3);
  }

  .skeleton-avatar {
    width: 40px;
    height: 40px;
    border-radius: var(--radius-full);
    flex-shrink: 0;
  }

  .skeleton-meta {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    flex: 1;
  }

  .skeleton-name {
    width: 120px;
    height: 14px;
  }

  .skeleton-handle {
    width: 80px;
    height: 12px;
  }

  .skeleton-body {
    padding-inline-start: calc(40px + var(--space-3));
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-block-end: var(--space-3);
  }

  .skeleton-line {
    height: 12px;
  }

  .skeleton-line-full {
    width: 100%;
  }

  .skeleton-line-short {
    width: 60%;
  }

  .skeleton-actions {
    display: flex;
    gap: var(--space-6);
    padding-inline-start: calc(40px + var(--space-3));
  }

  .skeleton-action {
    width: 40px;
    height: 14px;
  }
</style>

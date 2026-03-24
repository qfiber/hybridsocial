<div class="skeleton-post" aria-hidden="true">
  <div class="skeleton-layout">
    <div class="skeleton-avatar skeleton-pulse"></div>
    <div class="skeleton-content">
      <div class="skeleton-header">
        <div class="skeleton-name skeleton-pulse"></div>
        <div class="skeleton-handle skeleton-pulse"></div>
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
        <div class="skeleton-action skeleton-pulse"></div>
      </div>
    </div>
  </div>
</div>

<style>
  .skeleton-post {
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 14px;
    padding: 24px;
  }

  .skeleton-pulse {
    background: var(--color-surface-container);
    border-radius: 6px;
    animation: pulse 1.5s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 0.4; }
    50% { opacity: 0.7; }
  }

  .skeleton-layout {
    display: flex;
    gap: 16px;
  }

  .skeleton-avatar {
    width: 48px;
    height: 48px;
    border-radius: 9999px;
    flex-shrink: 0;
  }

  .skeleton-content {
    flex: 1;
    min-width: 0;
  }

  .skeleton-header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-block-end: 12px;
  }

  .skeleton-name {
    width: 120px;
    height: 16px;
  }

  .skeleton-handle {
    width: 80px;
    height: 14px;
  }

  .skeleton-body {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-block-end: 16px;
  }

  .skeleton-line {
    height: 14px;
  }

  .skeleton-line-full {
    width: 100%;
  }

  .skeleton-line-short {
    width: 60%;
  }

  .skeleton-actions {
    display: flex;
    gap: 32px;
    max-width: 28rem;
  }

  .skeleton-action {
    width: 40px;
    height: 14px;
  }
</style>

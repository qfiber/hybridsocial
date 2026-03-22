<script lang="ts">
  import Toast from '$lib/components/ui/Toast.svelte';

  let { children } = $props();
</script>

<div class="auth-layout">
  <div class="auth-container">
    <div class="auth-logo">
      <svg width="40" height="40" viewBox="0 0 28 28" fill="none" aria-hidden="true">
        <circle cx="14" cy="14" r="14" fill="var(--color-primary)" />
        <text x="14" y="19" text-anchor="middle" fill="white" font-size="14" font-weight="700">H</text>
      </svg>
      <span class="auth-logo-text">HybridSocial</span>
    </div>
    {@render children()}
  </div>
</div>
<Toast />

<style>
  .auth-layout {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    padding: var(--space-4);
    background: linear-gradient(
      var(--gradient-direction, 135deg),
      var(--gradient-start, var(--color-primary)),
      var(--gradient-end, var(--color-accent))
    );
  }

  .auth-container {
    width: 100%;
    max-width: 420px;
    background: var(--color-surface-raised);
    border-radius: var(--radius-xl);
    padding: var(--space-8);
    box-shadow: var(--shadow-xl);
  }

  .auth-logo {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-3);
    margin-block-end: var(--space-8);
  }

  .auth-logo-text {
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--color-text);
  }
</style>

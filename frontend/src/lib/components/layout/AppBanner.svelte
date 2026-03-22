<script lang="ts">
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';
  import { getInstanceInfo } from '$lib/api/instance.js';

  let show = $state(false);
  let platform = $state<'ios' | 'android' | null>(null);
  let iosUrl = $state('');
  let androidUrl = $state('');
  let fdroidUrl = $state('');

  const DISMISSED_KEY = 'hybridsocial_app_banner_dismissed';

  onMount(async () => {
    if (!browser) return;

    // Don't show if already dismissed
    if (localStorage.getItem(DISMISSED_KEY)) return;

    // Don't show if already in standalone/PWA mode
    if (window.matchMedia('(display-mode: standalone)').matches) return;

    // Detect platform
    const ua = navigator.userAgent;
    if (/iPhone|iPad|iPod/.test(ua)) {
      platform = 'ios';
    } else if (/Android/.test(ua)) {
      platform = 'android';
    } else {
      return; // Desktop — don't show
    }

    // Fetch app URLs from instance info
    try {
      const info = await getInstanceInfo();
      const apps = (info as any).apps;
      if (!apps || !apps.banner_enabled) return;

      iosUrl = apps.ios || '';
      androidUrl = apps.android || '';
      fdroidUrl = apps.fdroid || '';

      // Only show if there's a relevant URL
      if (platform === 'ios' && iosUrl) {
        show = true;
      } else if (platform === 'android' && (androidUrl || fdroidUrl)) {
        show = true;
      }
    } catch {
      // Silently fail
    }
  });

  function dismiss() {
    show = false;
    localStorage.setItem(DISMISSED_KEY, 'true');
  }
</script>

{#if show}
  <div class="app-banner">
    <button class="banner-close" onclick={dismiss} aria-label="Dismiss">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
      </svg>
    </button>

    <div class="banner-icon">
      <img src="/icons/icon.svg" alt="HybridSocial" width="40" height="40" />
    </div>

    <div class="banner-text">
      <strong class="banner-title">Get the app</strong>
      <span class="banner-subtitle">HybridSocial works better with the app</span>
    </div>

    <div class="banner-actions">
      {#if platform === 'ios'}
        <a href={iosUrl} class="banner-btn" target="_blank" rel="noopener">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
          </svg>
          App Store
        </a>
      {:else if platform === 'android'}
        {#if androidUrl}
          <a href={androidUrl} class="banner-btn" target="_blank" rel="noopener">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M3.18 23.77L14.84 12 3.18.23a1 1 0 00-.18.58v22.38c0 .22.06.42.18.58zm1.5.63L16.83 13.6l-3.25-3.14L4.68 24.4zm.58-23.63L4.68-.37 13.58 10.4l3.25-3.14L4.68.4h.58zM21.15 10.95l-4.32-2.48L13.17 12l3.66 3.53 4.32-2.48c.58-.33.85-.77.85-1.05 0-.28-.27-.72-.85-1.05z"/>
            </svg>
            Google Play
          </a>
        {/if}
        {#if fdroidUrl}
          <a href={fdroidUrl} class="banner-btn banner-btn-outline" target="_blank" rel="noopener">
            F-Droid
          </a>
        {/if}
      {/if}
    </div>
  </div>
{/if}

<style>
  .app-banner {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    background: var(--color-surface);
    border-block-end: 1px solid var(--color-border);
    position: relative;
  }

  .banner-close {
    position: absolute;
    inset-block-start: var(--space-2);
    inset-inline-end: var(--space-2);
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    padding: var(--space-1);
    cursor: pointer;
    border-radius: var(--radius-sm);
  }

  .banner-close:hover {
    color: var(--color-text-secondary);
    background: var(--color-border);
  }

  .banner-icon {
    flex-shrink: 0;
  }

  .banner-icon img {
    border-radius: var(--radius-md);
  }

  .banner-text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  .banner-title {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .banner-subtitle {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .banner-actions {
    display: flex;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  .banner-btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-1) var(--space-3);
    background: var(--color-primary);
    color: var(--color-primary-contrast, #fff);
    border: none;
    border-radius: var(--radius-full);
    font-size: var(--text-xs);
    font-weight: 600;
    text-decoration: none;
    white-space: nowrap;
    cursor: pointer;
  }

  .banner-btn:hover {
    opacity: 0.9;
    text-decoration: none;
  }

  .banner-btn-outline {
    background: transparent;
    color: var(--color-primary);
    border: 1px solid var(--color-primary);
  }

  /* Only show on mobile */
  @media (min-width: 769px) {
    .app-banner {
      display: none;
    }
  }
</style>

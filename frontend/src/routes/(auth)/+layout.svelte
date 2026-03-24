<script lang="ts">
  import { onMount } from 'svelte';
  import Toast from '$lib/components/ui/Toast.svelte';
  import { cookieConsent, hasConsented } from '$lib/stores/consent.js';
  import CookieBanner from '$lib/components/ui/CookieBanner.svelte';

  let { children } = $props();
  let floatingReady = $state(false);
  let consented = $state(hasConsented());

  cookieConsent.subscribe((v) => (consented = v));

  onMount(() => {
    // Start idle float only after entrance animations finish
    setTimeout(() => floatingReady = true, 1600);
  });
</script>

<div class="landing-outer" data-sveltekit-reload>
<div class="landing">
  <!-- Left: Hero / Marketing -->
  <div class="landing-hero">
    <div class="landing-hero-inner">
      <div class="hero-logo">
        <svg width="36" height="36" viewBox="0 0 28 28" fill="none" aria-hidden="true">
          <rect rx="6" width="28" height="28" fill="var(--color-primary)" />
          <text x="14" y="19.5" text-anchor="middle" fill="white" font-size="15" font-weight="700">H</text>
        </svg>
        <span class="hero-logo-text">HybridSocial</span>
      </div>

      <h1 class="hero-headline">
        Own your<br />social network<span class="hero-dot">.</span>
      </h1>

      <p class="hero-description">
        HybridSocial is a decentralized social platform.
        Run your own server, control your data, and connect
        with others across the Fediverse.
      </p>

      <div class="hero-features">
        <div class="hero-feature">
          <div class="hero-feature-icon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <rect x="2" y="3" width="20" height="14" rx="2" />
              <path d="M8 21h8" />
              <path d="M12 17v4" />
            </svg>
          </div>
          <h3 class="hero-feature-title">You host it</h3>
          <p class="hero-feature-desc">Run your own server or choose a provider</p>
        </div>
        <div class="hero-feature">
          <div class="hero-feature-icon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="5" r="3" />
              <circle cx="5" cy="19" r="3" />
              <circle cx="19" cy="19" r="3" />
              <path d="M12 8v4l-5 5" />
              <path d="M12 12l5 5" />
            </svg>
          </div>
          <h3 class="hero-feature-title">You own it</h3>
          <p class="hero-feature-desc">Your data, your rules, your community</p>
        </div>
        <div class="hero-feature">
          <div class="hero-feature-icon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10" />
              <path d="M2 12h20" />
              <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
            </svg>
          </div>
          <h3 class="hero-feature-title">You're connected</h3>
          <p class="hero-feature-desc">Seamless access across the open social web</p>
        </div>
      </div>

      <!-- Decorative floating cards -->
      <div class="hero-cards" aria-hidden="true">
        <div class="hero-card hero-card-reactions" class:float-a={floatingReady}>
          <div class="reaction-row"><span>👍</span> Like</div>
          <div class="reaction-row"><span>❤️</span> Love</div>
          <div class="reaction-row"><span>🥰</span> Care</div>
          <div class="reaction-row"><span>😡</span> Angry</div>
          <div class="reaction-row"><span>😢</span> Sad</div>
          <div class="reaction-row"><span>😂</span> LOL</div>
          <div class="reaction-row"><span>😮</span> Wow</div>
        </div>

        <div class="hero-card hero-card-post" class:float-b={floatingReady}>
          <div class="mock-post-header">
            <div class="mock-avatar"></div>
            <div>
              <div class="mock-name">John Smith</div>
              <div class="mock-handle">@john · 2h</div>
            </div>
          </div>
          <p class="mock-text">Just published a new post on my server! Loving the sense of ownership and freedom here. 🌿</p>
          <div class="mock-image"></div>
          <div class="mock-actions">
            <span>❤️ 42</span>
            <span>🔁 12</span>
            <span>💬 8</span>
            <span>🔖</span>
          </div>
        </div>

        <div class="hero-card hero-card-visibility" class:float-c={floatingReady}>
          <div class="vis-title">Post visibility</div>
          <div class="vis-option vis-active">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20"/></svg>
            <div>
              <div class="vis-label">Public</div>
              <div class="vis-desc">Anyone on or off the network</div>
            </div>
          </div>
          <div class="vis-option">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/></svg>
            <div>
              <div class="vis-label">Followers</div>
              <div class="vis-desc">Only your followers</div>
            </div>
          </div>
          <div class="vis-option">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
            <div>
              <div class="vis-label">Group</div>
              <div class="vis-desc">Members of a group</div>
            </div>
          </div>
          <div class="vis-option">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 2L11 13"/><path d="M22 2L15 22l-4-9-9-4z"/></svg>
            <div>
              <div class="vis-label">Direct</div>
              <div class="vis-desc">Mentioned users only</div>
            </div>
          </div>
        </div>

        <div class="hero-card hero-card-group" class:float-d={floatingReady}>
          <div class="group-icon">#</div>
          <div class="group-name">Photography</div>
          <div class="group-handle">@photogroup</div>
          <p class="group-desc">A space for photographers to share and connect.</p>
          <div class="group-meta">
            <div class="group-avatars">
              <div class="group-avatar-dot"></div>
              <div class="group-avatar-dot"></div>
              <div class="group-avatar-dot"></div>
            </div>
            <span class="group-count">group · 1.2K members</span>
          </div>
          <button class="group-join" tabindex="-1">Request to Join</button>
        </div>
      </div>
    </div>
  </div>

  <!-- Right: Auth form -->
  <div class="landing-form">
    <div class="landing-form-inner">
      {@render children()}

      <footer class="landing-footer">
        <a href="/legal/about">About</a>
        <a href="/legal/privacy">Privacy</a>
        <a href="/legal/terms">Terms</a>
      </footer>
    </div>
  </div>
</div>
</div>
{#if !consented}
  <CookieBanner onaccept={() => consented = true} />
{/if}
<Toast />

<style>
  /* ---- Layout ---- */
  .landing-outer {
    overflow-x: hidden;
    min-height: 100vh;
  }

  .landing {
    display: flex;
    min-height: 100vh;
    max-width: 1400px;
    margin: 0 auto;
    position: relative;
  }

  .landing-hero {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-8) var(--space-8) var(--space-8) var(--space-12);
    position: relative;
    overflow: visible;
    background: linear-gradient(180deg, #f7f8fa 0%, #e8ecf1 100%);
  }

  /* Extend hero background to left edge of viewport */
  .landing-hero::before {
    content: '';
    position: absolute;
    top: 0;
    bottom: 0;
    right: 100%;
    width: 100vw;
    background: inherit;
  }

  .landing-hero-inner {
    max-width: 640px;
    width: 100%;
    position: relative;
    z-index: 1;
  }

  .landing-form {
    width: 420px;
    min-width: 360px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-8);
    position: relative;
    background: #f1f2f4;
  }

  /* Extend form background to right edge of viewport */
  .landing-form::before {
    content: '';
    position: absolute;
    top: 0;
    bottom: 0;
    left: 100%;
    width: 100vw;
    background: inherit;
  }

  .landing-form-inner {
    width: 100%;
    max-width: 380px;
  }

  /* ---- Hero content ---- */
  .hero-logo {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    margin-block-end: var(--space-12);
  }

  .hero-logo-text {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
  }

  .hero-headline {
    font-size: 3.5rem;
    font-weight: 800;
    line-height: 1.08;
    color: var(--color-text);
    margin-block-end: var(--space-6);
    letter-spacing: -0.02em;
  }

  .hero-dot {
    color: var(--color-primary);
  }

  .hero-description {
    font-size: var(--text-lg);
    line-height: 1.6;
    color: var(--color-text-secondary);
    margin-block-end: var(--space-10);
    max-width: 480px;
  }

  /* ---- Features row ---- */
  .hero-features {
    display: flex;
    gap: var(--space-8);
    margin-block-end: var(--space-12);
  }

  .hero-feature {
    flex: 1;
  }

  .hero-feature-icon {
    color: var(--color-primary);
    margin-block-end: var(--space-3);
  }

  .hero-feature-title {
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-1);
  }

  .hero-feature-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    line-height: 1.4;
  }

  /* ---- Decorative floating cards ---- */
  .hero-cards {
    position: relative;
    height: 320px;
    pointer-events: none;
  }

  .hero-card {
    position: absolute;
    background: white;
    border-radius: var(--radius-xl);
    padding: var(--space-4);
    box-shadow: 0 4px 24px rgba(0, 0, 0, 0.08);
  }

  /* Reactions card */
  .hero-card-reactions {
    left: 0;
    top: 60px;
    width: 130px;
    z-index: 3;
  }

  .reaction-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: 3px 0;
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  /* Post card */
  .hero-card-post {
    left: 100px;
    top: 20px;
    width: 280px;
    z-index: 2;
  }

  .mock-post-header {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin-block-end: var(--space-2);
  }

  .mock-avatar {
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    background: linear-gradient(135deg, #d1d5db, #9ca3af);
    flex-shrink: 0;
  }

  .mock-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .mock-handle {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .mock-text {
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: 1.5;
    margin-block-end: var(--space-3);
  }

  .mock-image {
    width: 100%;
    height: 120px;
    border-radius: var(--radius-lg);
    background: linear-gradient(135deg, #3b7a6e, #2d5a4f);
    margin-block-end: var(--space-3);
  }

  .mock-actions {
    display: flex;
    gap: var(--space-4);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  /* Visibility card */
  .hero-card-visibility {
    left: 300px;
    top: 80px;
    width: 200px;
    z-index: 2;
  }

  .vis-title {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    margin-block-end: var(--space-3);
  }

  .vis-option {
    display: flex;
    align-items: flex-start;
    gap: var(--space-2);
    padding: var(--space-2) 0;
    color: var(--color-text-secondary);
  }

  .vis-option svg {
    flex-shrink: 0;
    margin-top: 2px;
  }

  .vis-active {
    color: var(--color-primary);
  }

  .vis-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .vis-active .vis-label {
    color: var(--color-primary);
  }

  .vis-desc {
    font-size: 0.65rem;
    color: var(--color-text-tertiary);
  }

  /* Group card */
  .hero-card-group {
    left: 360px;
    top: -10px;
    width: 190px;
    z-index: 1;
  }

  .group-icon {
    width: 36px;
    height: 36px;
    border-radius: var(--radius-md);
    background: var(--color-primary);
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: var(--text-lg);
    font-weight: 700;
    margin-block-end: var(--space-2);
  }

  .group-name {
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--color-text);
  }

  .group-handle {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-end: var(--space-2);
  }

  .group-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    line-height: 1.4;
    margin-block-end: var(--space-3);
  }

  .group-meta {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin-block-end: var(--space-3);
  }

  .group-avatars {
    display: flex;
    gap: -4px;
  }

  .group-avatar-dot {
    width: 16px;
    height: 16px;
    border-radius: var(--radius-full);
    background: linear-gradient(135deg, #d1d5db, #9ca3af);
    margin-inline-start: -4px;
    border: 1.5px solid white;
  }

  .group-avatar-dot:first-child {
    margin-inline-start: 0;
  }

  .group-count {
    font-size: 0.65rem;
    color: var(--color-text-tertiary);
  }

  .group-join {
    display: block;
    width: 100%;
    padding: var(--space-1) var(--space-3);
    background: transparent;
    border: 1.5px solid var(--color-primary);
    border-radius: var(--radius-full);
    color: var(--color-primary);
    font-size: var(--text-xs);
    font-weight: 600;
    cursor: default;
    text-align: center;
  }

  /* ---- Entrance animations ---- */
  @keyframes fadeUp {
    from {
      opacity: 0;
      transform: translateY(18px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideInLeft {
    from {
      opacity: 0;
      transform: translateX(-24px);
    }
    to {
      opacity: 1;
      transform: translateX(0);
    }
  }

  @keyframes floatUp {
    from {
      opacity: 0;
      transform: translateY(30px) scale(0.97);
    }
    to {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
  }

  .hero-logo {
    animation: fadeIn 0.6s cubic-bezier(0.22, 1, 0.36, 1) both;
  }

  .hero-headline {
    animation: slideInLeft 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.1s both;
  }

  .hero-description {
    animation: fadeUp 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.2s both;
  }

  .hero-feature:nth-child(1) {
    animation: fadeUp 0.6s cubic-bezier(0.22, 1, 0.36, 1) 0.3s both;
  }

  .hero-feature:nth-child(2) {
    animation: fadeUp 0.6s cubic-bezier(0.22, 1, 0.36, 1) 0.4s both;
  }

  .hero-feature:nth-child(3) {
    animation: fadeUp 0.6s cubic-bezier(0.22, 1, 0.36, 1) 0.5s both;
  }

  .hero-card {
    will-change: transform, opacity;
  }

  .hero-card-reactions {
    animation: floatUp 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.5s both;
  }

  .hero-card-post {
    animation: floatUp 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.6s both;
  }

  .hero-card-visibility {
    animation: floatUp 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.7s both;
  }

  .hero-card-group {
    animation: floatUp 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.8s both;
  }

  /* Idle float — applied via JS after entrance completes */
  @keyframes idleA {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-5px); }
  }

  @keyframes idleB {
    0%, 100% { transform: translateY(0) rotate(0deg); }
    50% { transform: translateY(-6px) rotate(0.3deg); }
  }

  @keyframes idleC {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-4px); }
  }

  @keyframes idleD {
    0%, 100% { transform: translateY(0) rotate(0deg); }
    50% { transform: translateY(-5px) rotate(-0.3deg); }
  }

  .float-a {
    animation: idleA 6s cubic-bezier(0.37, 0, 0.63, 1) infinite;
  }

  .float-b {
    animation: idleB 7s cubic-bezier(0.37, 0, 0.63, 1) infinite;
  }

  .float-c {
    animation: idleC 5.5s cubic-bezier(0.37, 0, 0.63, 1) infinite;
  }

  .float-d {
    animation: idleD 6.5s cubic-bezier(0.37, 0, 0.63, 1) infinite;
  }

  .landing-form-inner {
    animation: fadeUp 0.6s cubic-bezier(0.22, 1, 0.36, 1) 0.15s both;
  }

  /* Respect reduced motion preference */
  @media (prefers-reduced-motion: reduce) {
    .hero-logo,
    .hero-headline,
    .hero-description,
    .hero-feature,
    .hero-card,
    .landing-form-inner,
    .float-a, .float-b, .float-c, .float-d {
      animation: none !important;
    }
  }

  /* ---- Footer ---- */
  .landing-footer {
    display: flex;
    justify-content: center;
    gap: var(--space-4);
    margin-block-start: var(--space-6);
    padding-block-start: var(--space-4);
    border-block-start: 1px solid var(--color-border);
  }

  .landing-footer a {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-decoration: none;
  }

  .landing-footer a:hover {
    color: var(--color-primary);
  }

  /* ---- Responsive ---- */
  @media (max-width: 1024px) {
    .hero-cards {
      display: none;
    }

    .hero-headline {
      font-size: 2.75rem;
    }
  }

  @media (max-width: 768px) {
    .landing {
      flex-direction: column;
    }

    .landing-hero {
      border-radius: 0 0 2rem 2rem;
      padding: var(--space-8) var(--space-6);
    }

    .landing-form {
      width: 100%;
      min-width: unset;
      padding: var(--space-6);
    }

    .landing-form-inner {
      max-width: 400px;
      margin: 0 auto;
    }

    .hero-headline {
      font-size: 2.25rem;
    }

    .hero-features {
      gap: var(--space-4);
    }

    .hero-description {
      font-size: var(--text-base);
    }
  }
</style>

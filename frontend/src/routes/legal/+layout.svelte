<script lang="ts">
  let { children } = $props();
</script>

<div class="public-layout" data-sveltekit-reload>
  <header class="public-header">
    <div class="public-header-inner">
      <a href="/" class="public-logo">
        <svg width="28" height="28" viewBox="0 0 28 28" fill="none" aria-hidden="true">
          <rect rx="6" width="28" height="28" fill="var(--color-primary)" />
          <text x="14" y="19.5" text-anchor="middle" fill="white" font-size="15" font-weight="700">H</text>
        </svg>
        <span>HybridSocial</span>
      </a>
      <nav class="public-header-nav">
        <a href="/login" class="header-login-btn">Sign in</a>
      </nav>
    </div>
  </header>

  <div class="public-body">
    <main class="public-main">
      {@render children()}
    </main>

    <aside class="public-sidebar">
      <!-- Sign in card -->
      <div class="sidebar-card">
        <h3 class="sidebar-card-title">Sign in</h3>
        <p class="sidebar-card-text">Already have an account? Sign in to join the conversation.</p>
        <a href="/login" class="sidebar-btn sidebar-btn-primary">Sign in</a>
        <a href="/register" class="sidebar-btn sidebar-btn-outline">Create account</a>
      </div>

      <!-- Upsell card -->
      <div class="sidebar-card sidebar-card-promo">
        <div class="promo-badge">Managed hosting</div>
        <h3 class="sidebar-card-title">Launch your own server</h3>
        <p class="sidebar-card-text">
          Get a fully managed HybridSocial instance. We handle the infrastructure, updates, and security — you focus on building your community.
        </p>
        <ul class="promo-features">
          <li>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
            Your own domain &amp; branding
          </li>
          <li>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
            Automatic updates &amp; backups
          </li>
          <li>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
            Full federation support
          </li>
          <li>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
            Priority support
          </li>
        </ul>
        <a href="https://hybridsocial.io/hosting" class="sidebar-btn sidebar-btn-primary" target="_blank" rel="noopener">
          Get started &rarr;
        </a>
        <p class="promo-note">Plans start at $9/month</p>
      </div>

      <!-- Links card -->
      <div class="sidebar-card sidebar-card-links">
        <a href="/legal/about">About this server</a>
        <a href="/legal/privacy">Privacy Policy</a>
        <a href="/legal/terms">Terms of Service</a>
      </div>
    </aside>
  </div>

  <footer class="public-footer">
    <div class="public-footer-inner">
      <div class="footer-links">
        <a href="/legal/about">About</a>
        <a href="/legal/privacy">Privacy</a>
        <a href="/legal/terms">Terms</a>
      </div>
      <div class="footer-copy">&copy; {new Date().getFullYear()} HybridSocial</div>
    </div>
  </footer>
</div>

<style>
  .public-layout {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    background: #f5f6f8;
  }

  /* ---- Header ---- */
  .public-header {
    background: var(--color-surface-raised);
    border-block-end: 1px solid var(--color-border);
  }

  .public-header-inner {
    max-width: 1100px;
    margin: 0 auto;
    padding: var(--space-3) var(--space-6);
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .public-logo {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
    text-decoration: none;
  }

  .public-header-nav {
    display: flex;
    align-items: center;
    gap: var(--space-3);
  }

  .header-login-btn {
    padding: var(--space-1) var(--space-4);
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border-radius: var(--radius-lg);
    font-size: var(--text-sm);
    font-weight: 600;
    text-decoration: none;
    transition: background var(--transition-fast);
  }

  .header-login-btn:hover {
    background: var(--color-primary-hover);
    text-decoration: none;
  }

  /* ---- Body (content + sidebar) ---- */
  .public-body {
    flex: 1;
    display: flex;
    gap: var(--space-6);
    max-width: 1100px;
    width: 100%;
    margin: 0 auto;
    padding: var(--space-8) var(--space-6);
    align-items: flex-start;
  }

  .public-main {
    flex: 1;
    min-width: 0;
    background: var(--color-surface-raised);
    border-radius: var(--radius-xl);
    border: 1px solid var(--color-border);
    padding: var(--space-8);
  }

  /* ---- Sidebar ---- */
  .public-sidebar {
    width: 300px;
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    position: sticky;
    top: var(--space-8);
  }

  .sidebar-card {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-5);
  }

  .sidebar-card-title {
    font-size: var(--text-base);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .sidebar-card-text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.5;
    margin-block-end: var(--space-4);
  }

  .sidebar-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    padding: var(--space-2) var(--space-4);
    border-radius: var(--radius-lg);
    font-size: var(--text-sm);
    font-weight: 600;
    text-decoration: none;
    transition: background var(--transition-fast), border-color var(--transition-fast);
    margin-block-end: var(--space-2);
  }

  .sidebar-btn-primary {
    background: var(--color-primary);
    color: var(--color-text-on-primary);
  }

  .sidebar-btn-primary:hover {
    background: var(--color-primary-hover);
    text-decoration: none;
  }

  .sidebar-btn-outline {
    background: transparent;
    color: var(--color-primary);
    border: 1px solid var(--color-border);
  }

  .sidebar-btn-outline:hover {
    border-color: var(--color-primary);
    background: var(--color-primary-soft);
    text-decoration: none;
  }

  /* ---- Promo card ---- */
  .sidebar-card-promo {
    background: linear-gradient(180deg, #f0fdfa 0%, var(--color-surface-raised) 100%);
    border-color: var(--color-primary-soft);
  }

  .promo-badge {
    display: inline-block;
    font-size: 0.65rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--color-primary);
    background: var(--color-primary-soft);
    padding: 2px 8px;
    border-radius: var(--radius-full);
    margin-block-end: var(--space-3);
  }

  .promo-features {
    list-style: none;
    padding: 0;
    margin: 0 0 var(--space-4) 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .promo-features li {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  .promo-features li svg {
    flex-shrink: 0;
  }

  .promo-note {
    text-align: center;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-2);
    margin-block-end: 0;
  }

  /* ---- Links card ---- */
  .sidebar-card-links {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding: var(--space-4) var(--space-5);
  }

  .sidebar-card-links a {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    text-decoration: none;
  }

  .sidebar-card-links a:hover {
    color: var(--color-primary);
  }

  /* ---- Footer ---- */
  .public-footer {
    border-block-start: 1px solid var(--color-border);
    background: var(--color-surface-raised);
  }

  .public-footer-inner {
    max-width: 1100px;
    margin: 0 auto;
    padding: var(--space-5) var(--space-6);
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .footer-links {
    display: flex;
    gap: var(--space-5);
  }

  .footer-links a {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    text-decoration: none;
  }

  .footer-links a:hover {
    color: var(--color-primary);
  }

  .footer-copy {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
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

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .public-header {
    animation: fadeIn 0.4s ease both;
  }

  .public-main {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.05s both;
  }

  .public-sidebar .sidebar-card:nth-child(1) {
    animation: fadeUp 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.15s both;
  }

  .public-sidebar .sidebar-card:nth-child(2) {
    animation: fadeUp 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.25s both;
  }

  .public-sidebar .sidebar-card:nth-child(3) {
    animation: fadeUp 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.35s both;
  }

  .public-footer {
    animation: fadeIn 0.5s ease 0.3s both;
  }

  /* Subtle hover effects */
  .sidebar-card {
    transition: box-shadow 0.3s ease, transform 0.3s ease;
  }

  .sidebar-card:hover {
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.05);
  }

  .sidebar-card-promo:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 16px rgba(13, 148, 136, 0.1);
  }

  .sidebar-btn {
    transition: background var(--transition-fast), border-color var(--transition-fast), transform 0.15s ease;
  }

  .sidebar-btn:active {
    transform: scale(0.985);
  }

  .header-login-btn {
    transition: background var(--transition-fast), transform 0.15s ease;
  }

  .header-login-btn:active {
    transform: scale(0.96);
  }

  @media (prefers-reduced-motion: reduce) {
    .public-header,
    .public-main,
    .sidebar-card,
    .public-footer {
      animation: none !important;
    }

    .sidebar-card:hover,
    .sidebar-card-promo:hover {
      transform: none;
    }
  }

  /* ---- Responsive ---- */
  @media (max-width: 868px) {
    .public-sidebar {
      display: none;
    }
  }

  @media (max-width: 640px) {
    .public-main {
      padding: var(--space-5);
    }

    .public-footer-inner {
      flex-direction: column;
      gap: var(--space-3);
      text-align: center;
    }
  }
</style>

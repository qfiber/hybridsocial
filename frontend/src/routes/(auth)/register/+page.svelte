<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { ApiError } from '$lib/api/client.js';
  import { solvePow, type PowChallenge, type PowSolution } from '$lib/utils/pow.js';

  let handle = $state('');
  let email = $state('');
  let password = $state('');
  let passwordConfirm = $state('');
  let agreedToTerms = $state(false);
  let error = $state('');
  let fieldErrors = $state<Record<string, string>>({});
  let loading = $state(false);
  let success = $state(false);

  // PoW
  let powSolution = $state<PowSolution | null>(null);
  let powSolving = $state(false);

  // Turnstile
  let turnstileToken = $state('');
  let turnstileEnabled = $state(false);
  let turnstileContainer: HTMLDivElement | undefined = $state();

  // Tier plans
  interface TierLimits {
    char_limit: number;
    markdown: string;
    video_resolution: number;
    video_duration: number;
    image_size_mb: number;
    video_size_mb: number;
    media_per_post: number;
    poll_options: number;
    edit_window: number;
    pinned_posts: number;
    profile_fields: number;
    scheduled_posts: boolean;
    custom_emoji: boolean;
    follows_limit: number;
  }

  interface Plan {
    id: string;
    name: string;
    price: number;
    currency: string;
    limits: TierLimits;
  }

  let plans = $state<Plan[]>([]);
  let tiersEnabled = $state(false);
  let paymentConfigured = $state(false);
  let selectedTier = $state('free');
  let showTiers = $state(false);

  let passwordMismatch = $derived(
    passwordConfirm.length > 0 && password !== passwordConfirm
  );

  let formValid = $derived(
    handle.length > 0 &&
    email.length > 0 &&
    password.length >= 16 &&
    password === passwordConfirm &&
    agreedToTerms &&
    !powSolving
  );

  onMount(() => {
    fetchPowChallenge();
    checkTurnstile();
    fetchPlans();
  });

  async function fetchPlans() {
    try {
      const data = await api.get<{ plans: Plan[]; tiers_enabled: boolean; payment_configured: boolean }>('/api/v1/subscriptions/plans');
      plans = data.plans;
      tiersEnabled = data.tiers_enabled;
      paymentConfigured = data.payment_configured;
    } catch {
      // Plans not available
    }
  }

  async function fetchPowChallenge() {
    try {
      powSolving = true;
      const challenge = await api.get<PowChallenge>('/api/v1/auth/pow-challenge');
      powSolution = await solvePow(challenge);
    } catch {
      powSolution = null;
    } finally {
      powSolving = false;
    }
  }

  async function checkTurnstile() {
    try {
      const info = await api.get<{ turnstile_enabled?: boolean; turnstile_site_key?: string }>('/api/v1/instance/info');
      if (info.turnstile_enabled && info.turnstile_site_key) {
        turnstileEnabled = true;
        loadTurnstileScript(info.turnstile_site_key);
      }
    } catch { /* */ }
  }

  function loadTurnstileScript(siteKey: string) {
    if (typeof document === 'undefined') return;
    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileLoad';
    script.async = true;
    (window as unknown as Record<string, unknown>).onTurnstileLoad = () => {
      if (turnstileContainer) {
        (window as unknown as Record<string, { render: (el: HTMLElement, opts: Record<string, unknown>) => void }>).turnstile.render(
          turnstileContainer,
          { sitekey: siteKey, callback: (token: string) => { turnstileToken = token; } }
        );
      }
    };
    document.head.appendChild(script);
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault();
    error = '';
    fieldErrors = {};

    if (password !== passwordConfirm) {
      fieldErrors.password_confirm = 'Passwords do not match';
      return;
    }

    loading = true;
    try {
      const body: Record<string, unknown> = { handle, email, password };
      if (powSolution) body.pow_solution = powSolution;
      if (turnstileEnabled && turnstileToken) body.turnstile_token = turnstileToken;

      await api.post('/api/v1/auth/register', body);
      success = true;
    } catch (err) {
      if (err instanceof ApiError) {
        error = err.body.error_description || err.body.error || 'Registration failed';
        if (err.body.details) {
          fieldErrors = {};
          for (const [field, messages] of Object.entries(err.body.details)) {
            fieldErrors[field] = messages[0];
          }
        }
      } else {
        error = 'An unexpected error occurred. Please try again.';
      }
    } finally {
      loading = false;
    }
  }

  function formatPrice(cents: number, currency: string): string {
    if (cents === 0) return 'Free';
    return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(cents / 100);
  }

  function formatEditWindow(seconds: number): string {
    if (seconds === 0) return 'Unlimited';
    if (seconds < 3600) return `${Math.round(seconds / 60)} min`;
    if (seconds < 86400) return `${Math.round(seconds / 3600)} hours`;
    return `${Math.round(seconds / 86400)} days`;
  }

  function formatFollows(limit: number): string {
    return limit === 0 ? 'Unlimited' : String(limit);
  }
</script>

<svelte:head>
  <title>Create account - HybridSocial</title>
</svelte:head>

{#if success}
  <div class="auth-card">
    <div class="auth-success-icon" aria-hidden="true">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
        <polyline points="22 4 12 14.01 9 11.01"/>
      </svg>
    </div>
    <h1 class="auth-title" style="text-align: center;">Check your email</h1>
    <p class="auth-subtitle" style="text-align: center;">
      We sent a confirmation link to <strong>{email}</strong>.
      Please check your inbox and click the link to activate your account.
    </p>
    <p class="auth-footer">
      <a href="/login" class="auth-footer-link">Back to login</a>
    </p>
  </div>
{:else}
  <div class="register-layout">
    <!-- Left: Registration form -->
    <div class="auth-card">
      <div class="auth-logo">
        <svg width="40" height="40" viewBox="0 0 28 28" fill="none" aria-hidden="true">
          <rect rx="6" width="28" height="28" fill="var(--color-primary)" />
          <text x="14" y="19.5" text-anchor="middle" fill="white" font-size="15" font-weight="700">H</text>
        </svg>
      </div>

      <h1 class="auth-title">Create your account</h1>
      <p class="auth-subtitle">Join the conversation</p>

      {#if error}
        <div class="auth-error" role="alert">
          <span class="auth-error-icon" aria-hidden="true">!</span>
          {error}
        </div>
      {/if}

      <form onsubmit={handleSubmit} novalidate>
        <div class="auth-field">
          <label for="handle" class="auth-label">HANDLE</label>
          <div class="auth-handle-wrap">
            <span class="auth-handle-prefix" aria-hidden="true">@</span>
            <input id="handle" type="text" class="auth-input auth-handle-input" class:auth-input-error={!!fieldErrors.handle} placeholder="yourname" bind:value={handle} required disabled={loading} autocomplete="username" pattern="[a-zA-Z0-9_]+" />
          </div>
          {#if fieldErrors.handle}
            <p class="auth-field-error" role="alert">{fieldErrors.handle}</p>
          {/if}
        </div>

        <div class="auth-field">
          <label for="reg-email" class="auth-label">EMAIL</label>
          <input id="reg-email" type="email" class="auth-input" class:auth-input-error={!!fieldErrors.email} placeholder="you@example.com" bind:value={email} required disabled={loading} autocomplete="email" />
          {#if fieldErrors.email}
            <p class="auth-field-error" role="alert">{fieldErrors.email}</p>
          {/if}
        </div>

        <div class="auth-field">
          <label for="reg-password" class="auth-label">PASSWORD</label>
          <input id="reg-password" type="password" class="auth-input" class:auth-input-error={!!fieldErrors.password} placeholder="At least 16 characters" bind:value={password} required minlength={16} disabled={loading} autocomplete="new-password" />
          {#if fieldErrors.password}
            <p class="auth-field-error" role="alert">{fieldErrors.password}</p>
          {/if}
        </div>

        <div class="auth-field">
          <label for="reg-password-confirm" class="auth-label">CONFIRM PASSWORD</label>
          <input id="reg-password-confirm" type="password" class="auth-input" class:auth-input-error={passwordMismatch} placeholder="Repeat your password" bind:value={passwordConfirm} required disabled={loading} autocomplete="new-password" />
          {#if passwordMismatch}
            <p class="auth-field-error" role="alert">Passwords do not match</p>
          {/if}
        </div>

        {#if turnstileEnabled}
          <div class="auth-field">
            <div bind:this={turnstileContainer}></div>
          </div>
        {/if}

        <div class="auth-field auth-checkbox-field">
          <label class="auth-checkbox-label">
            <input type="checkbox" bind:checked={agreedToTerms} disabled={loading} class="auth-checkbox" />
            <span class="auth-checkbox-text">
              I agree to the <a href="/legal/terms" target="_blank" rel="noopener" class="auth-link">Terms of Service</a>
              and <a href="/legal/privacy" target="_blank" rel="noopener" class="auth-link">Privacy Policy</a>
            </span>
          </label>
        </div>

        {#if powSolving}
          <p class="auth-pow-status">
            <span class="auth-spinner-small" aria-hidden="true"></span>
            Solving challenge...
          </p>
        {/if}

        <button type="submit" class="auth-submit" disabled={loading || !formValid}>
          {#if loading}
            <span class="auth-spinner" aria-hidden="true"></span>
            Creating account...
          {:else}
            Create account
          {/if}
        </button>
      </form>

      <p class="auth-footer">
        Already have an account? <a href="/login" class="auth-footer-link">Log in</a>
      </p>
    </div>

    <!-- Right: Plans & tiers -->
    {#if tiersEnabled && plans.length > 0}
      <div class="plans-section">
        <h2 class="plans-title">Choose your plan</h2>
        <p class="plans-subtitle">Start free, upgrade anytime</p>

        <div class="plans-grid">
          {#each plans as plan (plan.id)}
            <button
              type="button"
              class="plan-card"
              class:plan-selected={selectedTier === plan.id}
              class:plan-popular={plan.id === 'verified_creator'}
              onclick={() => selectedTier = plan.id}
            >
              {#if plan.id === 'verified_creator'}
                <span class="plan-badge">Most popular</span>
              {/if}

              <h3 class="plan-name">{plan.name}</h3>
              <div class="plan-price">
                <span class="plan-amount">{formatPrice(plan.price, plan.currency)}</span>
                {#if plan.price > 0}
                  <span class="plan-period">/month</span>
                {/if}
              </div>

              <ul class="plan-features">
                <li>
                  <span class="plan-check">&#10003;</span>
                  {plan.limits.char_limit} character limit
                </li>
                <li>
                  <span class="plan-check">&#10003;</span>
                  {plan.limits.media_per_post} media per post
                </li>
                <li>
                  <span class="plan-check">&#10003;</span>
                  Edit window: {formatEditWindow(plan.limits.edit_window)}
                </li>
                <li>
                  <span class="plan-check">&#10003;</span>
                  {plan.limits.pinned_posts} pinned {plan.limits.pinned_posts === 1 ? 'post' : 'posts'}
                </li>
                <li>
                  <span class="plan-check">&#10003;</span>
                  Follows: {formatFollows(plan.limits.follows_limit)}
                </li>
                {#if plan.limits.scheduled_posts}
                  <li><span class="plan-check">&#10003;</span> Scheduled posts</li>
                {/if}
                {#if plan.limits.custom_emoji}
                  <li><span class="plan-check">&#10003;</span> Custom emoji</li>
                {/if}
                {#if plan.limits.markdown !== 'none'}
                  <li><span class="plan-check">&#10003;</span> Markdown ({plan.limits.markdown})</li>
                {/if}
                <li class="plan-feature-muted">
                  Up to {plan.limits.image_size_mb}MB images, {plan.limits.video_size_mb}MB video
                </li>
                {#if plan.limits.video_resolution >= 1080}
                  <li><span class="plan-check">&#10003;</span> HD video (1080p)</li>
                {/if}
              </ul>
            </button>
          {/each}
        </div>

        {#if !paymentConfigured && plans.some(p => p.price > 0)}
          <p class="plans-note">Payment processing coming soon. All accounts start on the Free plan.</p>
        {/if}

        <button type="button" class="plans-compare-btn" onclick={() => showTiers = !showTiers}>
          {showTiers ? 'Hide' : 'Compare all'} features
          <span class="material-symbols-outlined" style="font-size: 18px">{showTiers ? 'expand_less' : 'expand_more'}</span>
        </button>

        {#if showTiers}
          <div class="compare-table-wrap">
            <table class="compare-table">
              <thead>
                <tr>
                  <th>Feature</th>
                  {#each plans as plan (plan.id)}
                    <th class:compare-highlight={selectedTier === plan.id}>{plan.name}</th>
                  {/each}
                </tr>
              </thead>
              <tbody>
                <tr><td>Character limit</td>{#each plans as p (p.id)}<td>{p.limits.char_limit}</td>{/each}</tr>
                <tr><td>Media per post</td>{#each plans as p (p.id)}<td>{p.limits.media_per_post}</td>{/each}</tr>
                <tr><td>Image size</td>{#each plans as p (p.id)}<td>{p.limits.image_size_mb} MB</td>{/each}</tr>
                <tr><td>Video size</td>{#each plans as p (p.id)}<td>{p.limits.video_size_mb} MB</td>{/each}</tr>
                <tr><td>Video quality</td>{#each plans as p (p.id)}<td>{p.limits.video_resolution}p</td>{/each}</tr>
                <tr><td>Video duration</td>{#each plans as p (p.id)}<td>{Math.round(p.limits.video_duration / 60)} min</td>{/each}</tr>
                <tr><td>Poll options</td>{#each plans as p (p.id)}<td>{p.limits.poll_options}</td>{/each}</tr>
                <tr><td>Edit window</td>{#each plans as p (p.id)}<td>{formatEditWindow(p.limits.edit_window)}</td>{/each}</tr>
                <tr><td>Pinned posts</td>{#each plans as p (p.id)}<td>{p.limits.pinned_posts}</td>{/each}</tr>
                <tr><td>Profile fields</td>{#each plans as p (p.id)}<td>{p.limits.profile_fields}</td>{/each}</tr>
                <tr><td>Follows limit</td>{#each plans as p (p.id)}<td>{formatFollows(p.limits.follows_limit)}</td>{/each}</tr>
                <tr><td>Scheduled posts</td>{#each plans as p (p.id)}<td>{p.limits.scheduled_posts ? '&#10003;' : '&#10007;'}</td>{/each}</tr>
                <tr><td>Custom emoji</td>{#each plans as p (p.id)}<td>{p.limits.custom_emoji ? '&#10003;' : '&#10007;'}</td>{/each}</tr>
                <tr><td>Markdown</td>{#each plans as p (p.id)}<td>{p.limits.markdown}</td>{/each}</tr>
                <tr><td class="compare-price-row">Price</td>{#each plans as p (p.id)}<td class="compare-price-row">{formatPrice(p.price, p.currency)}{p.price > 0 ? '/mo' : ''}</td>{/each}</tr>
              </tbody>
            </table>
          </div>
        {/if}
      </div>
    {/if}
  </div>
{/if}

<style>
  .register-layout {
    display: flex;
    gap: 32px;
    align-items: flex-start;
    max-width: 960px;
    margin: 0 auto;
    padding: 0 16px;
  }

  /* ---- Auth Card ---- */
  .auth-card {
    background: white;
    border-radius: 14px;
    padding: 32px;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04), 0 4px 24px rgba(0, 0, 0, 0.06);
    flex: 1;
    min-width: 0;
    max-width: 420px;
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.1s both;
  }

  .auth-card:focus-within {
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.04), 0 8px 32px rgba(0, 0, 0, 0.08);
  }

  .auth-logo { display: flex; justify-content: center; margin-block-end: 24px; }
  .auth-title { font-family: 'Manrope', var(--font-sans); font-size: 1.25rem; font-weight: 700; color: var(--color-text); margin-block-end: 4px; }
  .auth-subtitle { font-size: 0.875rem; color: #6b7280; margin-block-end: 24px; }
  .auth-success-icon { display: flex; justify-content: center; margin-block-end: 16px; color: #16a34a; }

  .auth-error { display: flex; align-items: center; gap: 8px; padding: 12px 16px; margin-block-end: 16px; background: #fef2f2; border-radius: 10px; color: #dc2626; font-size: 0.875rem; }
  .auth-error-icon { display: inline-flex; align-items: center; justify-content: center; width: 20px; height: 20px; border-radius: 50%; background: #dc2626; color: white; font-size: 0.75rem; font-weight: 700; flex-shrink: 0; }

  .auth-field { margin-block-end: 16px; }
  .auth-label { display: block; font-size: 0.6875rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; color: #6b7280; margin-block-end: 6px; margin-inline-start: 4px; }
  .auth-input { display: block; width: 100%; height: 46px; padding: 0 16px; background: #e6e8e9; border: none; border-radius: 10px; font-size: 0.875rem; color: var(--color-text); transition: background-color 0.2s ease, box-shadow 0.2s ease; }
  .auth-input::placeholder { color: #9ca3af; }
  .auth-input:focus { outline: none; background: white; box-shadow: 0 0 0 2px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2); }
  .auth-input:disabled { opacity: 0.5; cursor: not-allowed; }
  .auth-input-error { box-shadow: 0 0 0 2px #fca5a5; }

  .auth-handle-wrap { position: relative; display: flex; align-items: center; }
  .auth-handle-prefix { position: absolute; inset-inline-start: 16px; color: #9ca3af; font-size: 0.875rem; pointer-events: none; }
  .auth-handle-input { padding-inline-start: 32px; }
  .auth-field-error { font-size: 0.75rem; color: #dc2626; margin-block-start: 4px; margin-inline-start: 4px; }

  .auth-checkbox-field { margin-block-start: 20px; }
  .auth-checkbox-label { display: flex; align-items: flex-start; gap: 10px; cursor: pointer; }
  .auth-checkbox { margin-block-start: 2px; accent-color: var(--color-primary); flex-shrink: 0; width: 16px; height: 16px; }
  .auth-checkbox-text { font-size: 0.8125rem; color: #6b7280; line-height: 1.5; }
  .auth-link { color: var(--color-primary); text-decoration: none; font-weight: 500; }
  .auth-link:hover { opacity: 0.8; }

  .auth-pow-status { display: flex; align-items: center; gap: 8px; font-size: 0.75rem; color: #6b7280; margin-block-end: 12px; }
  .auth-spinner-small { display: inline-block; width: 12px; height: 12px; border: 2px solid #9ca3af; border-inline-end-color: transparent; border-radius: 50%; animation: spin 0.6s linear infinite; }

  .auth-submit { display: flex; align-items: center; justify-content: center; gap: 8px; width: 100%; height: 46px; margin-block-start: 20px; padding: 0 20px; background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-primary-hover, var(--color-primary)) 100%); color: white; border: none; border-radius: 9999px; font-size: 0.875rem; font-weight: 600; cursor: pointer; box-shadow: 0 4px 14px rgba(var(--color-primary-rgb, 59, 130, 246), 0.25); transition: box-shadow 0.15s ease, transform 0.1s ease, opacity 0.15s ease; }
  .auth-submit:hover:not(:disabled) { box-shadow: 0 6px 20px rgba(var(--color-primary-rgb, 59, 130, 246), 0.35); }
  .auth-submit:active:not(:disabled) { transform: scale(0.985); }
  .auth-submit:disabled { opacity: 0.6; cursor: not-allowed; }

  .auth-footer { text-align: center; margin-block-start: 24px; font-size: 0.875rem; color: #6b7280; }
  .auth-footer-link { color: var(--color-primary); text-decoration: none; font-weight: 500; }
  .auth-footer-link:hover { opacity: 0.8; }

  .auth-spinner { display: inline-block; width: 16px; height: 16px; border: 2px solid currentColor; border-inline-end-color: transparent; border-radius: 50%; animation: spin 0.6s linear infinite; }

  @keyframes spin { to { transform: rotate(360deg); } }
  @keyframes fadeUp {
    from { opacity: 0; transform: translateY(16px); }
    to { opacity: 1; transform: translateY(0); }
  }

  @media (prefers-reduced-motion: reduce) { .auth-card { animation: none !important; } }

  /* ---- Plans Section ---- */
  .plans-section {
    flex: 1;
    min-width: 0;
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.2s both;
  }

  .plans-title {
    font-family: 'Manrope', var(--font-sans);
    font-size: 1.25rem;
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: 4px;
  }

  .plans-subtitle {
    font-size: 0.875rem;
    color: #6b7280;
    margin-block-end: 20px;
  }

  .plans-grid {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .plan-card {
    position: relative;
    text-align: start;
    padding: 16px 18px;
    background: white;
    border: 2px solid var(--color-border, #e5e7eb);
    border-radius: 14px;
    cursor: pointer;
    transition: border-color 150ms ease, box-shadow 150ms ease;
  }

  .plan-card:hover {
    border-color: var(--color-primary);
  }

  .plan-selected {
    border-color: var(--color-primary);
    box-shadow: 0 0 0 1px var(--color-primary), 0 4px 12px rgba(0, 106, 105, 0.1);
  }

  .plan-badge {
    position: absolute;
    top: -10px;
    inset-inline-end: 16px;
    background: var(--color-primary);
    color: white;
    font-size: 0.65rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 2px 10px;
    border-radius: 9999px;
  }

  .plan-name {
    font-size: 1rem;
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: 2px;
  }

  .plan-price {
    display: flex;
    align-items: baseline;
    gap: 2px;
    margin-block-end: 10px;
  }

  .plan-amount {
    font-size: 1.25rem;
    font-weight: 800;
    color: var(--color-text);
  }

  .plan-period {
    font-size: 0.75rem;
    color: #6b7280;
  }

  .plan-features {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-wrap: wrap;
    gap: 4px 16px;
  }

  .plan-features li {
    font-size: 0.75rem;
    color: var(--color-text);
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .plan-check {
    color: var(--color-primary);
    font-weight: 700;
    font-size: 0.7rem;
  }

  .plan-feature-muted {
    color: #9ca3af !important;
    font-size: 0.7rem !important;
  }

  .plans-note {
    font-size: 0.75rem;
    color: #9ca3af;
    text-align: center;
    margin-block-start: 12px;
  }

  /* Compare button */
  .plans-compare-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
    width: 100%;
    margin-block-start: 16px;
    padding: 8px;
    background: none;
    border: 1px solid var(--color-border, #e5e7eb);
    border-radius: 10px;
    color: var(--color-text-secondary);
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    transition: background 150ms ease;
  }

  .plans-compare-btn:hover {
    background: var(--color-surface, #f9fafb);
  }

  /* Compare table */
  .compare-table-wrap {
    margin-block-start: 12px;
    overflow-x: auto;
    border: 1px solid var(--color-border, #e5e7eb);
    border-radius: 12px;
    animation: fadeUp 0.2s ease;
  }

  .compare-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.75rem;
  }

  .compare-table th,
  .compare-table td {
    padding: 8px 10px;
    text-align: center;
    border-bottom: 1px solid var(--color-border, #f0f0f0);
  }

  .compare-table th {
    font-weight: 700;
    color: var(--color-text);
    background: var(--color-surface, #f9fafb);
    position: sticky;
    top: 0;
  }

  .compare-table th:first-child,
  .compare-table td:first-child {
    text-align: start;
    font-weight: 600;
    color: #6b7280;
  }

  .compare-highlight {
    color: var(--color-primary) !important;
  }

  .compare-price-row {
    font-weight: 700 !important;
    color: var(--color-text) !important;
    background: var(--color-surface, #f9fafb);
  }

  /* Responsive */
  @media (max-width: 768px) {
    .register-layout {
      flex-direction: column;
    }

    .auth-card {
      max-width: none;
    }
  }
</style>

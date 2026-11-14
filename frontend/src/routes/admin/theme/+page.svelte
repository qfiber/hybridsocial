<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { t } from '$lib/stores/i18n.js';
  import { t as tr } from '$lib/utils/i18n.js';
  import { getAdminTheme, saveAdminTheme, uploadLogo, uploadFavicon, uploadOgImage } from '$lib/api/admin.js';
  import { applyTheme, liftForDark, resolveFontFamily } from '$lib/stores/theme.js';
  import type { AdminThemeConfig } from '$lib/api/types.js';

  // Auto dark values, keyed by theme key. Mirrors what applyTheme() renders
  // for dark mode: everything here is the designed dark ramp from
  // :root[data-theme='dark'] in app.css (solid hex so a <input type=color>
  // can show it). Brand keys aren't listed — they lift from the light palette
  // (see DARK_LIFT_FROM). These are the fallbacks shown/previewed until an
  // admin pins a dark_* override.
  const DARK_RAMP: Record<string, string> = {
    color_primary_hover: '#a78bfa',
    color_primary_soft: '#2a2440',
    color_primary_contrast: '#ffffff',
    color_bg: '#0e0f15',
    color_bg_wash: '#1c1546',
    color_surface: '#1c1d27',
    color_border: '#2b2c39',
    color_text: '#f6f5fb',
    color_text_secondary: '#aeb0c2'
  };
  // Keys whose auto dark value is lifted from a light key (brand tracking),
  // matching liftForDark() in applyTheme().
  const DARK_LIFT_FROM: Record<string, string> = {
    color_primary: 'color_primary',
    color_secondary: 'color_secondary',
    color_accent: 'color_accent',
    color_text_link: 'color_primary',
    gradient_start: 'gradient_start',
    gradient_end: 'gradient_end'
  };

  // The auto (un-overridden) dark value for a key: lifted brand or ramp,
  // falling back to the light value (feedback colours stay saturated in dark).
  function darkAuto(key: string): string {
    const r = theme as unknown as Record<string, string>;
    if (DARK_LIFT_FROM[key]) return liftForDark(r[DARK_LIFT_FROM[key]] || '#000000');
    return DARK_RAMP[key] ?? r[key] ?? '#000000';
  }

  // Effective dark value for a key: the admin's override if set, else auto.
  function darkValue(key: string): string {
    const r = theme as unknown as Record<string, string>;
    return r['dark_' + key] || darkAuto(key);
  }

  const defaults: AdminThemeConfig = {
    color_primary: '#6c3edd',
    color_primary_hover: '#5a2fc4',
    color_primary_soft: '#ede9fc',
    color_primary_contrast: '#ffffff',
    color_secondary: '#6366f1',
    color_accent: '#8b6ee6',
    color_success: '#22c55e',
    color_warning: '#f59e0b',
    color_danger: '#ef4444',
    color_info: '#3b82f6',
    color_bg: '#ffffff',
    color_bg_wash: '#f4f1fd',
    color_surface: '#f8fafc',
    color_border: '#e2e8f0',
    color_text: '#0f172a',
    color_text_secondary: '#64748b',
    color_text_link: '#6c3edd',
    gradient_start: '#6c3edd',
    gradient_end: '#8b6ee6',
    gradient_direction: '135deg',
    border_radius: 'rounded',
    density: 'comfortable',
    font_family: 'system-ui',
    instance_name: '',
    instance_description: '',
    logo_url: null,
    favicon_url: null,
    og_image_url: null,
    mode: 'auto',
    dark_logo_url: null,
    // Dark overrides default to empty = auto-derived. Kept in the object so a
    // reset/clear is actually sent to the backend (it only writes keys it
    // receives), and render() treats an empty value as "derive it".
    dark_color_primary: '',
    dark_color_primary_hover: '',
    dark_color_primary_soft: '',
    dark_color_primary_contrast: '',
    dark_color_secondary: '',
    dark_color_accent: '',
    dark_color_success: '',
    dark_color_warning: '',
    dark_color_danger: '',
    dark_color_info: '',
    dark_color_bg: '',
    dark_color_bg_wash: '',
    dark_color_surface: '',
    dark_color_border: '',
    dark_color_text: '',
    dark_color_text_secondary: '',
    dark_color_text_link: ''
  };

  const modeOptions: { value: 'auto' | 'light' | 'dark'; label: string; hint: string }[] = [
    { value: 'auto', label: 'Auto', hint: "Follows each visitor's device setting" },
    { value: 'light', label: 'Light', hint: 'Always light' },
    { value: 'dark', label: 'Dark', hint: 'Always dark' }
  ];

  let theme: AdminThemeConfig = $state({ ...defaults });
  let loading = $state(true);
  let saving = $state(false);
  // Which variant the Live Preview renders. Lets the admin review the
  // auto-generated dark theme without changing the instance mode.
  let previewMode = $state<'light' | 'dark'>('light');
  // Which surface the preview shows. One theme drives both the app and the
  // admin panel, so the admin can check both before saving.
  let previewSurface = $state<'app' | 'admin'>('app');
  let previewLogo = $derived(
    previewMode === 'dark' ? theme.dark_logo_url || theme.logo_url : theme.logo_url || theme.dark_logo_url,
  );

  interface ColorEntry {
    key: keyof AdminThemeConfig;
    label: string;
  }

  const colorSections: { title: string; colors: ColorEntry[] }[] = [
    {
      title: 'Primary',
      colors: [
        { key: 'color_primary', label: 'Primary' },
        { key: 'color_primary_hover', label: 'Hover' },
        { key: 'color_primary_soft', label: 'Soft' },
        { key: 'color_primary_contrast', label: 'Contrast' }
      ]
    },
    {
      title: 'Brand',
      colors: [
        { key: 'color_secondary', label: 'Secondary' },
        { key: 'color_accent', label: 'Accent' }
      ]
    },
    {
      title: 'Feedback',
      colors: [
        { key: 'color_success', label: 'Success' },
        { key: 'color_warning', label: 'Warning' },
        { key: 'color_danger', label: 'Danger' },
        { key: 'color_info', label: 'Info' }
      ]
    },
    {
      title: 'Surfaces',
      colors: [
        { key: 'color_bg', label: 'Background' },
        { key: 'color_bg_wash', label: 'Background wash' },
        { key: 'color_surface', label: 'Surface' },
        { key: 'color_border', label: 'Border' }
      ]
    },
    {
      title: 'Text',
      colors: [
        { key: 'color_text', label: 'Primary Text' },
        { key: 'color_text_secondary', label: 'Secondary Text' },
        { key: 'color_text_link', label: 'Link Color' }
      ]
    }
  ];

  const fontOptions = [
    'system-ui',
    'Inter',
    'Roboto',
    'Open Sans',
    'Lato',
    'Montserrat',
    'Source Sans Pro',
    'Nunito',
    'Poppins'
  ];

  let previewVars = $derived(buildPreviewVars(previewMode));

  function buildPreviewVars(mode: 'light' | 'dark'): string {
    const radius =
      theme.border_radius === 'sharp' ? '2px' : theme.border_radius === 'pill' ? '9999px' : '8px';

    // Each colour resolves to the dark value (override, else auto-derived) in
    // dark mode, or the editable light value otherwise — so the preview always
    // reflects exactly what the pickers are editing.
    const r = theme as unknown as Record<string, string>;
    const v = (key: string) => (mode === 'dark' ? darkValue(key) : r[key]);

    return [
      `--p-primary: ${v('color_primary')}`,
      `--p-primary-hover: ${v('color_primary_hover')}`,
      `--p-primary-soft: ${v('color_primary_soft')}`,
      `--p-primary-contrast: ${v('color_primary_contrast')}`,
      `--p-secondary: ${v('color_secondary')}`,
      `--p-accent: ${v('color_accent')}`,
      `--p-success: ${v('color_success')}`,
      `--p-warning: ${v('color_warning')}`,
      `--p-danger: ${v('color_danger')}`,
      `--p-info: ${v('color_info')}`,
      `--p-bg: ${v('color_bg')}`,
      `--p-surface: ${v('color_surface')}`,
      `--p-border: ${v('color_border')}`,
      `--p-text: ${v('color_text')}`,
      `--p-text-secondary: ${v('color_text_secondary')}`,
      `--p-text-link: ${v('color_text_link')}`,
      `--p-gradient: linear-gradient(${theme.gradient_direction}, ${v('gradient_start')}, ${v('gradient_end')})`,
      `--p-radius: ${radius}`,
      `--p-font: ${resolveFontFamily(theme.font_family)}`
    ].join('; ');
  }

  function getContrastRatio(hex1: string, hex2: string): number {
    const l1 = relativeLuminance(hexToRgb(hex1));
    const l2 = relativeLuminance(hexToRgb(hex2));
    const lighter = Math.max(l1, l2);
    const darker = Math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  function hexToRgb(hex: string): [number, number, number] {
    const h = (hex || '#000000').replace('#', '');
    return [
      parseInt(h.substring(0, 2), 16) / 255,
      parseInt(h.substring(2, 4), 16) / 255,
      parseInt(h.substring(4, 6), 16) / 255
    ];
  }

  function relativeLuminance([r, g, b]: [number, number, number]): number {
    const toLinear = (c: number) => (c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
    return 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b);
  }

  function wcagLevel(ratio: number): { label: string; pass: boolean } {
    if (ratio >= 7) return { label: 'AAA', pass: true };
    if (ratio >= 4.5) return { label: 'AA', pass: true };
    if (ratio >= 3) return { label: 'AA Large', pass: true };
    return { label: 'Fail', pass: false };
  }

  // In dark preview mode the pickers edit the dark_* overrides (showing the
  // auto value until one is set); otherwise they edit the light palette.
  function getColorValue(key: keyof AdminThemeConfig): string {
    if (previewMode === 'dark') return darkValue(key as string);
    return (theme[key] as string) || '#000000';
  }

  function setColorValue(key: keyof AdminThemeConfig, value: string) {
    const field = previewMode === 'dark' ? 'dark_' + (key as string) : (key as string);
    (theme as unknown as Record<string, unknown>)[field] = value;
    theme = { ...theme };
  }

  // Whether a key currently has a dark override pinned (vs. auto-derived).
  function isDarkOverridden(key: keyof AdminThemeConfig): boolean {
    return !!(theme as unknown as Record<string, string>)['dark_' + (key as string)];
  }

  // Drop a dark override so the key reverts to its auto value.
  function clearDarkOverride(key: keyof AdminThemeConfig) {
    (theme as unknown as Record<string, unknown>)['dark_' + (key as string)] = '';
    theme = { ...theme };
  }

  // Background the WCAG badges contrast against — mode-aware.
  let contrastBg = $derived(previewMode === 'dark' ? darkValue('color_bg') : theme.color_bg);

  onMount(async () => {
    try {
      const serverTheme = await getAdminTheme();
      // Filter out null/undefined values so defaults aren't overridden
      const cleaned = Object.fromEntries(
        Object.entries(serverTheme).filter(([_, v]) => v != null && v !== '')
      );
      theme = { ...defaults, ...cleaned };
    } catch {
      // Use defaults
    } finally {
      loading = false;
    }
  });

  async function handleSave() {
    saving = true;
    try {
      // Instance name & description are edited on Instance › General and
      // written through the settings API. Strip them from the theme
      // payload so saving colors here never clobbers a value the operator
      // just changed there (the backend only writes keys it receives).
      const { instance_name: _n, instance_description: _d, ...payload } = theme;
      await saveAdminTheme(payload);
      // Push the new values into the live CSS vars so the admin
      // sees the change instantly — previously a full page reload
      // was required to pick up the saved theme.
      applyTheme(theme as unknown as import('$lib/api/types.js').ThemeConfig);
      addToast('Theme saved successfully', 'success');
    } catch {
      addToast('Failed to save theme', 'error');
    } finally {
      saving = false;
    }
  }

  function resetToDefaults() {
    theme = { ...defaults };
    addToast('Theme reset to defaults', 'info');
  }

  function exportTheme() {
    const json = JSON.stringify(theme, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'theme.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  function importTheme() {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json';
    input.onchange = async () => {
      const file = input.files?.[0];
      if (!file) return;
      try {
        const text = await file.text();
        const imported = JSON.parse(text) as Partial<AdminThemeConfig>;
        theme = { ...defaults, ...imported };
        addToast('Theme imported', 'success');
      } catch {
        addToast('Invalid theme file', 'error');
      }
    };
    input.click();
  }

  function setMode(mode: 'auto' | 'light' | 'dark') {
    theme.mode = mode;
    theme = { ...theme };
    // Live-apply so the admin sees the whole app flip while choosing.
    applyTheme(theme as unknown as import('$lib/api/types.js').ThemeConfig);
  }

  async function handleLogoUpload(e: Event) {
    const input = e.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    try {
      const result = await uploadLogo(file, 'light');
      theme.logo_url = result.url;
      theme = { ...theme };
      addToast('Logo uploaded', 'success');
    } catch {
      addToast('Failed to upload logo', 'error');
    }
  }

  async function handleDarkLogoUpload(e: Event) {
    const input = e.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    try {
      const result = await uploadLogo(file, 'dark');
      theme.dark_logo_url = result.url;
      theme = { ...theme };
      addToast('Dark logo uploaded', 'success');
    } catch {
      addToast('Failed to upload dark logo', 'error');
    }
  }

  async function handleFaviconUpload(e: Event) {
    const input = e.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    try {
      const result = await uploadFavicon(file);
      theme.favicon_url = result.url;
      theme = { ...theme };
      addToast('Favicon uploaded', 'success');
      if (result.app_icons === false) addToast(tr('admin.theme.app_icons_skipped'), 'info');
    } catch {
      addToast('Failed to upload favicon', 'error');
    }
  }

  async function handleOgImageUpload(e: Event) {
    const input = e.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    try {
      const result = await uploadOgImage(file);
      theme.og_image_url = result.url;
      theme = { ...theme };
      addToast('Social share image uploaded', 'success');
    } catch {
      addToast('Failed to upload social share image', 'error');
    }
  }

  let radiusValue = $derived(
    theme.border_radius === 'sharp' ? 0 : theme.border_radius === 'pill' ? 2 : 1
  );
</script>

<svelte:head>
  <title>Theme Editor - Admin</title>
</svelte:head>

{#if loading}
  <div class="theme-loading">
    <div class="skeleton" style="height: 100vh; width: 100%"></div>
  </div>
{:else}
  <div class="theme-editor">
    <div class="theme-controls">
      <h1 class="page-title">Theme Editor</h1>

      <div class="editing-banner" class:editing-dark={previewMode === 'dark'}>
        {#if previewMode === 'dark'}
          Editing the <strong>dark palette</strong>. Colours below set dark-mode
          overrides; leave one on <em>Auto</em> to derive it from your light theme.
          Switch the preview to Light to edit the light palette.
        {:else}
          Editing the <strong>light palette</strong>. Switch the preview
          (top-right) to <em>Dark</em> to customise dark-mode colours.
        {/if}
      </div>

      {#each colorSections as section (section.title)}
        <div class="color-section card">
          <h3 class="section-title">{section.title}</h3>
          <div class="color-grid">
            {#each section.colors as color (color.key)}
              {@const value = getColorValue(color.key)}
              {@const contrast = getContrastRatio(value, contrastBg)}
              {@const wcag = wcagLevel(contrast)}
              <div class="color-picker-group">
                <label class="color-label" for="color-{color.key}">{color.label}</label>
                <div class="color-inputs">
                  <input
                    type="color"
                    id="color-{color.key}"
                    value={value}
                    oninput={(e) => setColorValue(color.key, (e.currentTarget as HTMLInputElement).value)}
                    class="color-input"
                  />
                  <input
                    type="text"
                    value={value}
                    oninput={(e) => {
                      const v = (e.currentTarget as HTMLInputElement).value;
                      if (/^#[0-9a-fA-F]{6}$/.test(v)) setColorValue(color.key, v);
                    }}
                    class="hex-input input"
                    maxlength="7"
                  />
                  <span
                    class="wcag-badge"
                    class:wcag-pass={wcag.pass}
                    class:wcag-fail={!wcag.pass}
                    title="Contrast ratio: {contrast.toFixed(1)}:1"
                  >{wcag.label}</span>
                  {#if previewMode === 'dark'}
                    <button
                      type="button"
                      class="auto-chip"
                      class:auto-chip-on={isDarkOverridden(color.key)}
                      title={isDarkOverridden(color.key)
                        ? 'Pinned dark override — click to revert to the auto value'
                        : 'Auto (derived) — edit to pin a dark override'}
                      disabled={!isDarkOverridden(color.key)}
                      onclick={() => clearDarkOverride(color.key)}
                    >{isDarkOverridden(color.key) ? 'Auto ✕' : 'Auto'}</button>
                  {/if}
                </div>
              </div>
            {/each}
          </div>
        </div>
      {/each}

      <div class="shape-section card">
        <h3 class="section-title">Shape</h3>
        <div class="shape-control">
          <label class="color-label" for="radius-slider">Border Radius</label>
          <div class="radius-slider-row">
            <span class="radius-label">Sharp</span>
            <input
              type="range"
              id="radius-slider"
              min="0"
              max="2"
              step="1"
              value={radiusValue}
              oninput={(e) => {
                const v = Number((e.currentTarget as HTMLInputElement).value);
                theme.border_radius = v === 0 ? 'sharp' : v === 2 ? 'pill' : 'rounded';
                theme = { ...theme };
              }}
              class="range-input"
            />
            <span class="radius-label">Pill</span>
          </div>
        </div>
        <div class="shape-control">
          <label class="color-label">Layout Density</label>
          <div class="density-options">
            {#each ['compact', 'comfortable', 'spacious'] as d (d)}
              <label class="density-option" class:selected={theme.density === d}>
                <input
                  type="radio"
                  name="density"
                  value={d}
                  checked={theme.density === d}
                  onchange={() => { theme.density = d as AdminThemeConfig['density']; theme = { ...theme }; }}
                  class="visually-hidden"
                />
                <span>{d.charAt(0).toUpperCase() + d.slice(1)}</span>
              </label>
            {/each}
          </div>
        </div>
      </div>

      <div class="font-section card">
        <h3 class="section-title">Font</h3>
        <div class="font-control">
          <label class="color-label" for="font-select">Font Family</label>
          <select id="font-select" class="input" bind:value={theme.font_family} onchange={() => { theme = { ...theme }; }}>
            {#each fontOptions as font (font)}
              <option value={font}>{font === 'system-ui' ? 'System Default' : font}</option>
            {/each}
          </select>
          <input
            type="text"
            class="input"
            placeholder="Or enter a Google Font name..."
            oninput={(e) => {
              const v = (e.currentTarget as HTMLInputElement).value;
              if (v.trim()) {
                theme.font_family = v;
                theme = { ...theme };
              }
            }}
            style="margin-block-start: var(--space-2)"
          />
        </div>
      </div>

      <div class="gradient-section card">
        <h3 class="section-title">Gradient</h3>
        <div class="color-grid">
          <div class="color-picker-group">
            <label class="color-label" for="gradient-start">Start Color</label>
            <div class="color-inputs">
              <input type="color" id="gradient-start" bind:value={theme.gradient_start} oninput={() => { theme = { ...theme }; }} class="color-input" />
              <input type="text" bind:value={theme.gradient_start} class="hex-input input" maxlength="7" />
            </div>
          </div>
          <div class="color-picker-group">
            <label class="color-label" for="gradient-end">End Color</label>
            <div class="color-inputs">
              <input type="color" id="gradient-end" bind:value={theme.gradient_end} oninput={() => { theme = { ...theme }; }} class="color-input" />
              <input type="text" bind:value={theme.gradient_end} class="hex-input input" maxlength="7" />
            </div>
          </div>
          <div class="color-picker-group">
            <label class="color-label" for="gradient-dir">Direction</label>
            <input
              type="text"
              id="gradient-dir"
              class="input"
              bind:value={theme.gradient_direction}
              oninput={() => { theme = { ...theme }; }}
              placeholder="135deg"
            />
          </div>
        </div>
        <div class="gradient-preview-bar" style="background: linear-gradient({theme.gradient_direction}, {theme.gradient_start}, {theme.gradient_end})"></div>
      </div>

      <div class="darkmode-section card">
        <h3 class="section-title">Dark mode</h3>
        <p class="branding-hint">
          Dark is derived from your colours above by default. To customise it,
          flip the preview to Dark and edit the palette there. Pick how the
          instance renders below; you can also upload a dark logo under Branding.
        </p>
        <div class="mode-options" style="display:flex; gap:8px; flex-wrap:wrap;">
          {#each modeOptions as opt}
            <button
              type="button"
              class="btn {theme.mode === opt.value ? 'btn-primary' : 'btn-outline'}"
              onclick={() => setMode(opt.value)}
              title={opt.hint}
            >
              {opt.label}
            </button>
          {/each}
        </div>
      </div>

      <div class="branding-section card">
        <h3 class="section-title">Branding</h3>
        <p class="branding-hint">
          The instance name and description moved to
          <a href="/admin/instance/general">Instance &rsaquo; General</a>.
        </p>
        <div class="branding-fields">
          <div class="branding-field">
            <label class="color-label">Logo (light mode)</label>
            <div class="upload-row">
              {#if theme.logo_url}
                <img src={theme.logo_url} alt="Logo" class="upload-preview" />
              {/if}
              <input type="file" accept="image/*" onchange={handleLogoUpload} class="file-input" />
            </div>
          </div>
          <div class="branding-field">
            <label class="color-label">Logo (dark mode)</label>
            <p class="branding-hint">Shown when the theme is dark. Falls back to the light logo if unset.</p>
            <div class="upload-row">
              {#if theme.dark_logo_url}
                <img
                  src={theme.dark_logo_url}
                  alt="Dark logo"
                  class="upload-preview"
                  style="background:#14121c; padding:4px; border-radius:6px;"
                />
              {/if}
              <input type="file" accept="image/*" onchange={handleDarkLogoUpload} class="file-input" />
            </div>
          </div>
          <div class="branding-field">
            <label class="color-label">Favicon</label>
            <p class="branding-hint">{$t('admin.theme.favicon_hint')}</p>
            <div class="upload-row">
              {#if theme.favicon_url}
                <img src={theme.favicon_url} alt="Favicon" class="upload-preview upload-favicon" />
              {/if}
              <input type="file" accept="image/*" onchange={handleFaviconUpload} class="file-input" />
            </div>
          </div>
          <div class="branding-field">
            <label class="color-label">Social share image (OG)</label>
            <p class="branding-hint">
              Used when posts and instance pages are linked on other sites
              (Twitter, Slack, Discord, Mastodon cards). Recommended: 1200×630.
            </p>
            <div class="upload-row">
              {#if theme.og_image_url}
                <img src={theme.og_image_url} alt="Social share" class="upload-preview upload-og" />
              {/if}
              <input type="file" accept="image/*" onchange={handleOgImageUpload} class="file-input" />
            </div>
          </div>
        </div>
      </div>

      <div class="theme-actions">
        <button class="btn btn-ghost" type="button" onclick={resetToDefaults}>Reset to Defaults</button>
        <button class="btn btn-outline" type="button" onclick={importTheme}>Import JSON</button>
        <button class="btn btn-outline" type="button" onclick={exportTheme}>Export JSON</button>
        <button class="btn btn-primary" type="button" disabled={saving} onclick={handleSave}>
          {saving ? 'Saving...' : 'Save Theme'}
        </button>
      </div>
    </div>

    <div class="theme-preview-panel">
      <div class="preview-head">
        <h2 class="preview-title">Live Preview</h2>
        <div class="preview-mode-toggle" role="radiogroup" aria-label={$t('admin_theme_preview.surface_label')}>
          {#each ['app', 'admin'] as ps (ps)}
            <button
              type="button"
              role="radio"
              aria-checked={previewSurface === ps}
              class="preview-mode-btn"
              class:active={previewSurface === ps}
              onclick={() => (previewSurface = ps as 'app' | 'admin')}
            >
              {ps === 'app' ? $t('admin_theme_preview.app') : $t('admin_theme_preview.admin')}
            </button>
          {/each}
        </div>
        <div class="preview-mode-toggle" role="radiogroup" aria-label="Preview mode">
          {#each ['light', 'dark'] as pm (pm)}
            <button
              type="button"
              role="radio"
              aria-checked={previewMode === pm}
              class="preview-mode-btn"
              class:active={previewMode === pm}
              onclick={() => (previewMode = pm as 'light' | 'dark')}
            >
              {pm === 'light' ? 'Light' : 'Dark'}
            </button>
          {/each}
        </div>
      </div>
      {#if previewMode === 'dark'}
        <p class="preview-note">
          Previewing dark. The colour pickers on the left now edit the dark
          palette — surfaces and text included.
        </p>
      {/if}
      <div class="preview-frame" style={previewVars} data-preview-mode={previewMode}>
        {#if previewSurface === 'admin'}
          <!-- Admin panel: the same tokens, as the panel uses them. -->
          <div class="ap-shell">
            <aside class="ap-rail">
              <div class="ap-brand">
                {#if previewLogo}
                  <img src={previewLogo} alt="" class="ap-logo" />
                {:else}
                  <span class="ap-mark">{(theme.instance_name || 'H').trim()[0]?.toUpperCase()}</span>
                  <span class="ap-name">{theme.instance_name || 'HybridSocial'}</span>
                {/if}
                <span class="ap-sub">{$t('admin_shell.admin')}</span>
              </div>
              <span class="ap-cluster">{$t('admin_shell.cluster_operate')}</span>
              <span class="ap-item ap-item-active">{$t('admin_dashboard.title')}</span>
              <span class="ap-item">{$t('admin_theme_preview.reports')}</span>
              <span class="ap-item">{$t('admin_theme_preview.approvals')} <span class="ap-badge">3</span></span>
              <span class="ap-cluster">{$t('admin_shell.cluster_configure')}</span>
              <span class="ap-item">{$t('admin_settings.group.general')}</span>
            </aside>
            <div class="ap-main">
              <div class="ap-topbar">
                <span class="ap-crumb">{$t('admin_theme_preview.crumb')}</span>
                <span class="ap-search">{$t('admin_palette.open')}</span>
              </div>
              <div class="ap-content">
                <div class="ap-title">{$t('admin_dashboard.title')}</div>
                <div class="ap-tile">
                  <span class="ap-tile-count">3</span>
                  <span>{$t('admin_dashboard.queue.approvals', { count: 3 })}</span>
                </div>
                <div class="ap-card">
                  <div class="ap-row">
                    <span>{$t('admin_settings.require_email_confirmation')}</span>
                    <span class="ap-toggle" aria-hidden="true"></span>
                  </div>
                  <div class="ap-row">
                    <span>{$t('admin_settings.registration_mode')}</span>
                    <span class="ap-pill">{$t('admin_dashboard.all_clear')}</span>
                  </div>
                </div>
                <div class="ap-savebar">
                  <span>{$t('admin_shell.unsaved_changes')}</span>
                  <span class="ap-save">{$t('admin_shell.save')}</span>
                </div>
              </div>
            </div>
          </div>
        {:else}
        <!-- Header -->
        <div class="preview-header">
          <span class="preview-logo">{theme.instance_name || 'HybridSocial'}</span>
          <div class="preview-nav-dots">
            <span class="preview-dot"></span>
            <span class="preview-dot"></span>
            <span class="preview-dot"></span>
          </div>
        </div>

        <!-- Nav items -->
        <div class="preview-nav">
          <div class="preview-nav-item preview-nav-active">Home</div>
          <div class="preview-nav-item">Explore</div>
          <div class="preview-nav-item">Notifications</div>
        </div>

        <!-- Post card -->
        <div class="preview-card">
          <div class="preview-card-header">
            <div class="preview-avatar"></div>
            <div>
              <div class="preview-name">Jane Doe</div>
              <div class="preview-handle">@jane</div>
            </div>
          </div>
          <p class="preview-card-text">
            This is a sample post to preview how content looks with your chosen theme colors and typography settings.
          </p>
          <div class="preview-card-actions">
            <span class="preview-action">Reply</span>
            <span class="preview-action">Boost</span>
            <span class="preview-action">Like</span>
          </div>
        </div>

        <!-- Button row -->
        <div class="preview-buttons">
          <button type="button" class="preview-btn preview-btn-primary">Primary</button>
          <button type="button" class="preview-btn preview-btn-secondary">Secondary</button>
          <button type="button" class="preview-btn preview-btn-outline">Outline</button>
        </div>

        <!-- Alerts -->
        <div class="preview-alerts">
          <div class="preview-alert preview-alert-success">Success message</div>
          <div class="preview-alert preview-alert-warning">Warning message</div>
          <div class="preview-alert preview-alert-error">Error message</div>
        </div>

        <!-- Input -->
        <div class="preview-input-wrapper">
          <input type="text" class="preview-input" placeholder="Type something..." readonly />
        </div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .theme-loading {
    padding: var(--space-4);
  }

  .theme-editor {
    display: grid;
    grid-template-columns: 1fr 380px;
    gap: var(--space-6);
    align-items: start;
  }

  .theme-controls {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
  }

  .section-title {
    font-size: var(--text-base);
    font-weight: 600;
    margin-block-end: var(--space-3);
  }

  .color-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: var(--space-3);
  }

  .color-picker-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .color-label {
    font-size: var(--text-xs);
    font-weight: 500;
    color: var(--color-text-secondary);
    display: block;
  }

  .color-inputs {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .color-input {
    width: 36px;
    height: 36px;
    padding: 2px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    cursor: pointer;
    background: none;
  }

  .color-input::-webkit-color-swatch-wrapper {
    padding: 2px;
  }

  .color-input::-webkit-color-swatch {
    border: none;
    border-radius: var(--radius-sm);
  }

  .hex-input {
    width: 90px;
    font-family: var(--font-mono);
    font-size: var(--text-xs);
  }

  .wcag-badge {
    font-size: 10px;
    font-weight: 700;
    padding: 2px 6px;
    border-radius: var(--radius-full);
    white-space: nowrap;
  }

  .wcag-pass {
    background: var(--color-success-soft);
    color: var(--color-on-success-soft);
  }

  .wcag-fail {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
  }

  .auto-chip {
    font-size: 10px;
    font-weight: 700;
    padding: 2px 6px;
    border-radius: var(--radius-full);
    border: 1px solid var(--color-border);
    background: transparent;
    color: var(--color-text-tertiary);
    cursor: default;
    white-space: nowrap;
  }

  .auto-chip-on {
    border-color: var(--color-primary);
    background: var(--color-primary-soft);
    color: var(--color-primary);
    cursor: pointer;
  }

  .editing-banner {
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    border: 1px solid var(--color-border);
    background: var(--color-surface-container-low, rgba(0, 0, 0, 0.03));
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    line-height: 1.5;
  }

  .editing-banner.editing-dark {
    border-color: var(--color-primary);
    background: var(--color-primary-soft);
    color: var(--color-text);
  }

  .shape-control {
    margin-block-end: var(--space-3);
  }

  .radius-slider-row {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    margin-block-start: var(--space-2);
  }

  .radius-label {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    white-space: nowrap;
  }

  .range-input {
    flex: 1;
    accent-color: var(--color-primary);
  }

  .density-options {
    display: flex;
    gap: var(--space-2);
    margin-block-start: var(--space-2);
  }

  .density-option {
    display: flex;
    align-items: center;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .density-option.selected {
    border-color: var(--color-primary);
    background: var(--color-primary-soft);
    color: var(--color-primary);
  }

  .font-control {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .gradient-preview-bar {
    height: 24px;
    border-radius: var(--radius-md);
    margin-block-start: var(--space-3);
  }

  .branding-fields {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .branding-field {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .upload-row {
    display: flex;
    align-items: center;
    gap: var(--space-3);
  }

  .upload-preview {
    width: 48px;
    height: 48px;
    object-fit: contain;
    border-radius: var(--radius-md);
    border: 1px solid var(--color-border);
  }

  .upload-favicon {
    width: 32px;
    height: 32px;
  }

  .upload-og {
    width: 120px;
    height: 63px;
  }

  .branding-hint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block: 4px 8px;
    line-height: 1.4;
  }

  .file-input {
    font-size: var(--text-sm);
  }

  .theme-actions {
    display: flex;
    gap: var(--space-2);
    flex-wrap: wrap;
    padding-block-start: var(--space-4);
    border-block-start: 1px solid var(--color-border);
  }

  .theme-actions .btn-primary {
    margin-inline-start: auto;
  }

  /* Preview Panel */
  .theme-preview-panel {
    position: sticky;
    top: var(--space-4);
  }

  .preview-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    margin-block-end: var(--space-3);
  }

  .preview-title {
    font-size: var(--text-base);
    font-weight: 600;
  }

  .preview-mode-toggle {
    display: inline-flex;
    padding: 2px;
    gap: 2px;
    background: var(--color-surface-container-low, rgba(0, 0, 0, 0.04));
    border-radius: var(--radius-full);
  }

  .preview-mode-btn {
    padding: 4px 12px;
    border: none;
    background: transparent;
    border-radius: var(--radius-full);
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .preview-mode-btn.active {
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
  }

  .preview-note {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    line-height: 1.4;
    margin-block-end: var(--space-2);
  }

  .preview-frame {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    overflow: hidden;
    background: var(--p-bg);
    color: var(--p-text);
    font-family: var(--p-font), system-ui, sans-serif;
    font-size: 13px;
  }

  .preview-frame[data-preview-mode='dark'] {
    color-scheme: dark;
  }

  .preview-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 16px;
    background: var(--p-gradient);
    color: var(--p-primary-contrast);
  }

  .preview-logo {
    font-weight: 700;
    font-size: 14px;
  }

  .preview-nav-dots {
    display: flex;
    gap: 4px;
  }

  .preview-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.5);
  }

  .preview-nav {
    display: flex;
    border-block-end: 1px solid var(--p-border);
    background: var(--p-surface);
  }

  .preview-nav-item {
    padding: 8px 14px;
    font-size: 12px;
    color: var(--p-text-secondary);
    cursor: default;
  }

  .preview-nav-active {
    color: var(--p-primary);
    font-weight: 600;
    border-block-end: 2px solid var(--p-primary);
  }

  .preview-card {
    margin: 12px;
    padding: 12px;
    background: var(--p-surface);
    border: 1px solid var(--p-border);
    border-radius: var(--p-radius);
  }

  .preview-card-header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-block-end: 8px;
  }

  .preview-avatar {
    width: 32px;
    height: 32px;
    border-radius: 50%;
    background: var(--p-primary-soft);
  }

  .preview-name {
    font-weight: 600;
    font-size: 13px;
  }

  .preview-handle {
    font-size: 11px;
    color: var(--p-text-secondary);
  }

  .preview-card-text {
    font-size: 13px;
    line-height: 1.5;
    margin-block-end: 8px;
  }

  .preview-card-actions {
    display: flex;
    gap: 16px;
  }

  .preview-action {
    font-size: 11px;
    color: var(--p-text-secondary);
  }

  .preview-buttons {
    display: flex;
    gap: 8px;
    padding: 0 12px 12px;
  }

  .preview-btn {
    padding: 6px 12px;
    border: 1px solid transparent;
    border-radius: var(--p-radius);
    font-size: 12px;
    font-weight: 500;
    cursor: default;
  }

  .preview-btn-primary {
    background: var(--p-primary);
    color: var(--p-primary-contrast);
  }

  .preview-btn-secondary {
    background: var(--p-secondary);
    color: white;
  }

  .preview-btn-outline {
    background: transparent;
    color: var(--p-primary);
    border-color: var(--p-border);
  }

  .preview-alerts {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 0 12px;
  }

  .preview-alert {
    padding: 8px 12px;
    border-radius: var(--p-radius);
    font-size: 12px;
    font-weight: 500;
  }

  .preview-alert-success {
    background: color-mix(in srgb, var(--p-success) 15%, transparent);
    color: var(--p-success);
  }

  .preview-alert-warning {
    background: color-mix(in srgb, var(--p-warning) 15%, transparent);
    color: var(--p-warning);
  }

  .preview-alert-error {
    background: color-mix(in srgb, var(--p-danger) 15%, transparent);
    color: var(--p-danger);
  }

  .preview-input-wrapper {
    padding: 12px;
  }

  .preview-input {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid var(--p-border);
    border-radius: var(--p-radius);
    font-size: 12px;
    background: var(--p-bg);
    color: var(--p-text);
    font-family: inherit;
  }

  .preview-input::placeholder {
    color: var(--p-text-secondary);
  }

  @media (max-width: 1024px) {
    .theme-editor {
      grid-template-columns: 1fr;
    }

    .theme-preview-panel {
      position: static;
      order: -1;
    }
  }

  /* Admin panel preview */
  .ap-shell {
    display: flex;
    min-height: 340px;
  }

  .ap-rail {
    display: flex;
    flex-direction: column;
    gap: 2px;
    width: 38%;
    padding: 10px 8px;
    background: var(--p-surface);
    border-inline-end: 1px solid var(--p-border);
  }

  .ap-brand {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 2px 6px;
    padding: 2px 4px 8px;
    margin-block-end: 4px;
    border-block-end: 1px solid var(--p-border);
  }

  .ap-logo {
    height: 20px;
    max-width: 100%;
    object-fit: contain;
  }

  .ap-mark {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 20px;
    height: 20px;
    border-radius: 6px;
    background: var(--p-primary);
    color: var(--p-primary-contrast);
    font-size: 11px;
    font-weight: 700;
  }

  .ap-name {
    font-weight: 700;
    font-size: 12px;
  }

  .ap-sub {
    flex-basis: 100%;
    font-size: 10px;
    font-weight: 600;
    color: var(--p-primary);
  }

  .ap-cluster {
    margin-block-start: 6px;
    padding: 0 6px;
    font-size: 10px;
    font-weight: 700;
  }

  .ap-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 5px 6px;
    border-radius: var(--p-radius);
    font-size: 11px;
    color: var(--p-text-secondary);
  }

  .ap-item-active {
    background: var(--p-primary-soft);
    color: var(--p-primary);
    font-weight: 600;
  }

  .ap-badge {
    padding: 0 5px;
    border-radius: 9999px;
    background: var(--p-danger);
    color: var(--p-primary-contrast);
    font-size: 9px;
    font-weight: 700;
  }

  .ap-main {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  .ap-topbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
    padding: 8px 10px;
    border-block-end: 1px solid var(--p-border);
    font-size: 11px;
  }

  .ap-crumb {
    color: var(--p-text-secondary);
  }

  .ap-search {
    padding: 2px 8px;
    border: 1px solid var(--p-border);
    border-radius: 9999px;
    color: var(--p-text-secondary);
    font-size: 10px;
  }

  .ap-content {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 10px;
  }

  .ap-title {
    font-size: 15px;
    font-weight: 700;
  }

  .ap-tile {
    display: flex;
    align-items: baseline;
    gap: 6px;
    padding: 8px 10px;
    border-radius: var(--p-radius);
    border-inline-start: 3px solid var(--p-warning);
    background: var(--p-surface);
    font-size: 11px;
  }

  .ap-tile-count {
    font-size: 16px;
    font-weight: 700;
  }

  .ap-card {
    border: 1px solid var(--p-border);
    border-radius: var(--p-radius);
    background: var(--p-surface);
  }

  .ap-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 7px 10px;
    font-size: 11px;
  }

  .ap-row + .ap-row {
    border-block-start: 1px solid var(--p-border);
  }

  .ap-toggle {
    position: relative;
    width: 26px;
    height: 14px;
    border-radius: 9999px;
    background: var(--p-primary);
  }

  .ap-toggle::after {
    content: '';
    position: absolute;
    inset-block-start: 2px;
    inset-inline-end: 2px;
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--p-primary-contrast);
  }

  .ap-pill {
    padding: 1px 8px;
    border-radius: 9999px;
    background: color-mix(in srgb, var(--p-success) 18%, transparent);
    color: var(--p-success);
    font-size: 10px;
    font-weight: 600;
  }

  .ap-savebar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
    padding: 6px 8px;
    border: 1px solid var(--p-border);
    border-radius: var(--p-radius);
    background: var(--p-surface);
    font-size: 11px;
  }

  .ap-save {
    white-space: nowrap;
    padding: 3px 10px;
    border-radius: var(--p-radius);
    background: var(--p-primary);
    color: var(--p-primary-contrast);
    font-weight: 600;
  }
</style>

<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getAdminTheme, saveAdminTheme, uploadLogo, uploadFavicon } from '$lib/api/admin.js';
  import type { AdminThemeConfig } from '$lib/api/types.js';

  const defaults: AdminThemeConfig = {
    color_primary: '#0d9488',
    color_primary_hover: '#0f766e',
    color_primary_soft: '#ccfbf1',
    color_primary_contrast: '#ffffff',
    color_secondary: '#6366f1',
    color_accent: '#14b8a6',
    color_success: '#22c55e',
    color_warning: '#f59e0b',
    color_danger: '#ef4444',
    color_info: '#3b82f6',
    color_bg: '#ffffff',
    color_surface: '#f8fafc',
    color_border: '#e2e8f0',
    color_text: '#0f172a',
    color_text_secondary: '#64748b',
    color_text_link: '#0d9488',
    gradient_start: '#0d9488',
    gradient_end: '#14b8a6',
    gradient_direction: '135deg',
    border_radius: 'rounded',
    density: 'comfortable',
    font_family: 'system-ui',
    instance_name: '',
    instance_description: '',
    logo_url: null,
    favicon_url: null
  };

  let theme: AdminThemeConfig = $state({ ...defaults });
  let loading = $state(true);
  let saving = $state(false);

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

  let previewVars = $derived(buildPreviewVars());

  function buildPreviewVars(): string {
    return [
      `--p-primary: ${theme.color_primary}`,
      `--p-primary-hover: ${theme.color_primary_hover}`,
      `--p-primary-soft: ${theme.color_primary_soft}`,
      `--p-primary-contrast: ${theme.color_primary_contrast}`,
      `--p-secondary: ${theme.color_secondary}`,
      `--p-accent: ${theme.color_accent}`,
      `--p-success: ${theme.color_success}`,
      `--p-warning: ${theme.color_warning}`,
      `--p-danger: ${theme.color_danger}`,
      `--p-info: ${theme.color_info}`,
      `--p-bg: ${theme.color_bg}`,
      `--p-surface: ${theme.color_surface}`,
      `--p-border: ${theme.color_border}`,
      `--p-text: ${theme.color_text}`,
      `--p-text-secondary: ${theme.color_text_secondary}`,
      `--p-text-link: ${theme.color_text_link}`,
      `--p-gradient: linear-gradient(${theme.gradient_direction}, ${theme.gradient_start}, ${theme.gradient_end})`,
      `--p-radius: ${theme.border_radius === 'sharp' ? '2px' : theme.border_radius === 'pill' ? '9999px' : '8px'}`,
      `--p-font: ${theme.font_family}`
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

  function getColorValue(key: keyof AdminThemeConfig): string {
    return (theme[key] as string) || '#000000';
  }

  function setColorValue(key: keyof AdminThemeConfig, value: string) {
    (theme as unknown as Record<string, unknown>)[key] = value;
    theme = { ...theme };
  }

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
      await saveAdminTheme(theme);
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

  async function handleLogoUpload(e: Event) {
    const input = e.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    try {
      const result = await uploadLogo(file);
      theme.logo_url = result.url;
      theme = { ...theme };
      addToast('Logo uploaded', 'success');
    } catch {
      addToast('Failed to upload logo', 'error');
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
    } catch {
      addToast('Failed to upload favicon', 'error');
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

      {#each colorSections as section (section.title)}
        <div class="color-section card">
          <h3 class="section-title">{section.title}</h3>
          <div class="color-grid">
            {#each section.colors as color (color.key)}
              {@const value = getColorValue(color.key)}
              {@const contrast = getContrastRatio(value, theme.color_bg)}
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

      <div class="branding-section card">
        <h3 class="section-title">Branding</h3>
        <div class="branding-fields">
          <div class="branding-field">
            <label class="color-label" for="instance-name">Instance Name</label>
            <input id="instance-name" type="text" class="input" bind:value={theme.instance_name} />
          </div>
          <div class="branding-field">
            <label class="color-label" for="instance-desc">Instance Description</label>
            <textarea id="instance-desc" class="textarea" rows="3" bind:value={theme.instance_description}></textarea>
          </div>
          <div class="branding-field">
            <label class="color-label">Logo</label>
            <div class="upload-row">
              {#if theme.logo_url}
                <img src={theme.logo_url} alt="Logo" class="upload-preview" />
              {/if}
              <input type="file" accept="image/*" onchange={handleLogoUpload} class="file-input" />
            </div>
          </div>
          <div class="branding-field">
            <label class="color-label">Favicon</label>
            <div class="upload-row">
              {#if theme.favicon_url}
                <img src={theme.favicon_url} alt="Favicon" class="upload-preview upload-favicon" />
              {/if}
              <input type="file" accept="image/*" onchange={handleFaviconUpload} class="file-input" />
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
      <h2 class="preview-title">Live Preview</h2>
      <div class="preview-frame" style={previewVars}>
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
    color: #166534;
  }

  .wcag-fail {
    background: var(--color-danger-soft);
    color: #991b1b;
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

  .preview-title {
    font-size: var(--text-base);
    font-weight: 600;
    margin-block-end: var(--space-3);
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
</style>

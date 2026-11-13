<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import {
    getEmailTemplates, updateEmailTemplate, resetEmailTemplate, previewEmailTemplate,
    type EmailTemplate, type EmailTemplatePreview
  } from '$lib/api/admin.js';

  let templates: EmailTemplate[] = $state([]);
  let loading = $state(true);
  let selectedKey = $state<string | null>(null);

  let draftSubject = $state('');
  let draftHtml = $state('');
  let draftEnabled = $state(true);
  let saving = $state(false);
  let previewing = $state(false);
  let resetting = $state(false);
  let preview: EmailTemplatePreview | null = $state(null);

  let selectedTemplate = $derived(
    templates.find((t) => t.key === selectedKey) || null
  );

  let dirty = $derived(
    selectedTemplate !== null &&
    (
      draftSubject !== selectedTemplate.subject ||
      draftHtml !== selectedTemplate.html_body ||
      draftEnabled !== selectedTemplate.enabled
    )
  );

  onMount(async () => {
    try {
      templates = await getEmailTemplates();
      if (templates.length > 0) selectTemplate(templates[0].key);
    } catch {
      addToast('Failed to load email templates', 'error');
    } finally {
      loading = false;
    }
  });

  function selectTemplate(key: string) {
    const t = templates.find((x) => x.key === key);
    if (!t) return;
    selectedKey = key;
    draftSubject = t.subject;
    draftHtml = t.html_body;
    draftEnabled = t.enabled;
    preview = null;
    runPreview(true);
  }

  async function runPreview(fromSaved = false) {
    if (!selectedTemplate) return;
    previewing = true;
    try {
      preview = await previewEmailTemplate(
        selectedTemplate.key,
        fromSaved ? undefined : { subject: draftSubject, html_body: draftHtml }
      );
    } catch {
      addToast('Failed to render preview', 'error');
    } finally {
      previewing = false;
    }
  }

  async function handleSave() {
    if (!selectedTemplate) return;
    saving = true;
    try {
      await updateEmailTemplate(selectedTemplate.key, {
        subject: draftSubject,
        html_body: draftHtml,
        enabled: draftEnabled
      });
      addToast('Template saved', 'success');
      templates = await getEmailTemplates();
      selectTemplate(selectedTemplate.key);
    } catch (err: unknown) {
      const e = err as { body?: { error?: string; details?: Record<string, string[]> } };
      if (e?.body?.details) {
        const firstField = Object.keys(e.body.details)[0];
        addToast(`${firstField}: ${e.body.details[firstField][0]}`, 'error');
      } else {
        addToast('Failed to save template', 'error');
      }
    } finally {
      saving = false;
    }
  }

  async function handleReset() {
    if (!selectedTemplate) return;
    if (!confirm(`Reset "${selectedTemplate.name}" back to the built-in default? Your current customizations will be discarded.`)) return;
    resetting = true;
    try {
      await resetEmailTemplate(selectedTemplate.key);
      addToast('Reset to default', 'success');
      templates = await getEmailTemplates();
      selectTemplate(selectedTemplate.key);
    } catch {
      addToast('Failed to reset', 'error');
    } finally {
      resetting = false;
    }
  }

  function insertVariable(varName: string) {
    const ta = document.getElementById('html-body') as HTMLTextAreaElement | null;
    if (!ta) return;
    const start = ta.selectionStart;
    const end = ta.selectionEnd;
    const token = `{{${varName}}}`;
    draftHtml = draftHtml.slice(0, start) + token + draftHtml.slice(end);
    queueMicrotask(() => {
      ta.focus();
      ta.selectionStart = ta.selectionEnd = start + token.length;
    });
  }
</script>

<div class="templates-panel">
  <p class="panel-sub">Customise transactional emails sent by the instance. Unchecked <em>enabled</em> or a missing template falls back to the built-in default.</p>

  {#if loading}
    <div class="skeleton" style="height: 300px"></div>
  {:else}
    <div class="layout">
      <aside class="template-list">
        {#each templates as t (t.key)}
          <button
            type="button"
            class="template-item"
            class:selected={t.key === selectedKey}
            onclick={() => selectTemplate(t.key)}
          >
            <div class="template-item-head">
              <span class="template-item-name">{t.name}</span>
              {#if t.customized}
                <span class="template-item-badge">custom</span>
              {/if}
              {#if !t.enabled}
                <span class="template-item-badge badge-off">off</span>
              {/if}
            </div>
            <span class="template-item-key">{t.key}</span>
          </button>
        {/each}
      </aside>

      {#if selectedTemplate}
        <section class="editor">
          <header class="editor-head">
            <div>
              <h2 class="editor-title">{selectedTemplate.name}</h2>
              <p class="editor-desc">{selectedTemplate.description}</p>
            </div>
            <label class="editor-enabled">
              <input type="checkbox" bind:checked={draftEnabled} />
              <span>Enabled</span>
            </label>
          </header>

          <div class="field">
            <label for="subject" class="field-label">Subject</label>
            <input
              id="subject"
              type="text"
              class="input"
              bind:value={draftSubject}
              placeholder="Subject line"
            />
          </div>

          <div class="field">
            <div class="field-header">
              <label for="html-body" class="field-label">HTML body</label>
              <span class="field-hint">Write plain HTML with inline styles. Scripts, iframes, and event handlers are stripped on save.</span>
            </div>
            <textarea
              id="html-body"
              class="textarea html-textarea"
              bind:value={draftHtml}
              rows="18"
              spellcheck="false"
            ></textarea>
          </div>

          <div class="field">
            <div class="field-label">Variables (click to insert at cursor)</div>
            <div class="variable-chips">
              {#each Object.entries(selectedTemplate.variables) as [name, desc]}
                <button
                  type="button"
                  class="var-chip"
                  title={desc}
                  onclick={() => insertVariable(name)}
                >
                  <code>{`{{${name}}}`}</code>
                </button>
              {/each}
            </div>
          </div>

          <div class="editor-actions">
            <button class="btn btn-ghost" type="button" onclick={handleReset} disabled={resetting || !selectedTemplate.customized}>
              {resetting ? 'Resetting…' : 'Reset to default'}
            </button>
            <button class="btn btn-outline" type="button" onclick={() => runPreview(false)} disabled={previewing}>
              {previewing ? 'Rendering…' : 'Preview with sample data'}
            </button>
            <button class="btn btn-primary" type="button" onclick={handleSave} disabled={saving || !dirty}>
              {saving ? 'Saving…' : 'Save changes'}
            </button>
          </div>
        </section>

        <aside class="preview">
          <h3 class="preview-title">Preview</h3>
          {#if preview}
            <div class="preview-subject-row">
              <span class="preview-label">Subject</span>
              <span class="preview-subject">{preview.subject}</span>
            </div>
            <iframe
              class="preview-frame"
              title="Email preview"
              sandbox=""
              srcdoc={preview.html}
            ></iframe>
            <details class="preview-text">
              <summary>Plain-text fallback (auto-generated)</summary>
              <pre>{preview.text}</pre>
            </details>
          {:else if previewing}
            <div class="skeleton" style="height: 400px"></div>
          {:else}
            <p class="empty-text">Click "Preview with sample data" to render.</p>
          {/if}
        </aside>
      {/if}
    </div>
  {/if}
</div>

<style>
  .templates-panel {
    max-width: 1400px;
  }

  .panel-sub {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-4);
  }

  .layout {
    display: grid;
    grid-template-columns: 240px minmax(0, 1fr) minmax(0, 420px);
    gap: var(--space-4);
    align-items: flex-start;
  }

  .template-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .template-item {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: var(--space-3);
    text-align: start;
    background: transparent;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: background var(--transition-fast), border-color var(--transition-fast);
  }

  .template-item:hover {
    background: var(--color-surface);
  }

  .template-item.selected {
    border-color: var(--color-primary);
    background: var(--color-secondary-container);
  }

  .template-item-head {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    flex-wrap: wrap;
  }

  .template-item-name {
    font-weight: 600;
    font-size: var(--text-sm);
  }

  .template-item-badge {
    font-size: 0.65rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-primary);
    background: var(--color-surface);
    padding: 1px 6px;
    border-radius: var(--radius-full);
  }

  .template-item-badge.badge-off {
    color: var(--color-on-warning-soft);
    background: var(--color-warning-soft);
  }

  .template-item-key {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    font-family: var(--font-mono);
  }

  .editor {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    padding: var(--space-5);
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
  }

  .editor-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-3);
  }

  .editor-title {
    font-size: var(--text-lg);
    font-weight: 700;
    margin: 0 0 2px 0;
  }

  .editor-desc {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin: 0;
  }

  .editor-enabled {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: var(--text-sm);
    white-space: nowrap;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .field-label {
    font-size: var(--text-xs);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-secondary);
  }

  .field-header {
    display: flex;
    justify-content: space-between;
    gap: var(--space-2);
    align-items: baseline;
    flex-wrap: wrap;
  }

  .field-hint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .html-textarea {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    line-height: 1.5;
    resize: vertical;
  }

  .variable-chips {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-1);
  }

  .var-chip {
    padding: 2px var(--space-2);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    cursor: pointer;
    font-size: var(--text-xs);
  }

  .var-chip:hover {
    background: var(--color-secondary-container);
  }

  .var-chip code {
    font-family: var(--font-mono);
  }

  .editor-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    padding-block-start: var(--space-2);
    border-block-start: 1px solid var(--color-border);
  }

  .preview {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding: var(--space-4);
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    position: sticky;
    top: var(--space-4);
  }

  .preview-title {
    font-size: var(--text-sm);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-secondary);
    margin: 0;
  }

  .preview-subject-row {
    display: flex;
    gap: var(--space-2);
    padding: var(--space-2);
    background: var(--color-surface);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .preview-label {
    font-weight: 700;
    color: var(--color-text-secondary);
    flex-shrink: 0;
  }

  .preview-subject {
    word-break: break-word;
  }

  .preview-frame {
    width: 100%;
    height: 520px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: #f4f4f6;
  }

  .preview-text summary {
    cursor: pointer;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    padding: var(--space-1) 0;
  }

  .preview-text pre {
    font-size: var(--text-xs);
    font-family: var(--font-mono);
    white-space: pre-wrap;
    word-break: break-word;
    padding: var(--space-2);
    background: var(--color-surface);
    border-radius: var(--radius-sm);
    max-height: 240px;
    overflow: auto;
    margin: 0;
  }

  .empty-text {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    text-align: center;
    padding: var(--space-6) 0;
  }

  @media (max-width: 1200px) {
    .layout {
      grid-template-columns: 220px minmax(0, 1fr);
    }

    .preview {
      grid-column: 1 / -1;
      position: static;
    }
  }

  @media (max-width: 768px) {
    .layout {
      grid-template-columns: 1fr;
    }
  }
</style>

<script lang="ts">
  import { onMount } from 'svelte';
  import { SHORTCUTS, type ShortcutEntry } from '$lib/utils/shortcuts.js';

  let open = $state(false);

  function handleOpen() {
    open = true;
  }

  function handleClose() {
    open = false;
  }

  function handleKeydown(e: KeyboardEvent) {
    if (!open) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      handleClose();
    }
  }

  onMount(() => {
    window.addEventListener('open-shortcuts-help', handleOpen);
    return () => {
      window.removeEventListener('open-shortcuts-help', handleOpen);
    };
  });

  const groups: { id: ShortcutEntry['group']; label: string }[] = [
    { id: 'navigation', label: 'Navigation' },
    { id: 'compose', label: 'Compose' },
    { id: 'feed', label: 'Feed cursor' },
    { id: 'post', label: 'Focused post' },
    { id: 'help', label: 'Help' },
  ];

  function entriesFor(group: ShortcutEntry['group']) {
    return SHORTCUTS.filter((s) => s.group === group);
  }

  function renderKey(keys: string): string[] {
    return keys.split(/\s+\/\s+|\s+/).map((k) => k);
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if open}
  <div
    class="shortcuts-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="Keyboard shortcuts"
    onclick={handleClose}
  >
    <div class="shortcuts-panel" onclick={(e) => e.stopPropagation()}>
      <div class="shortcuts-header">
        <h2 class="shortcuts-title">Keyboard shortcuts</h2>
        <button
          type="button"
          class="shortcuts-close"
          onclick={handleClose}
          aria-label="Close keyboard shortcuts"
        >
          <span class="material-symbols-outlined">close</span>
        </button>
      </div>
      <div class="shortcuts-grid">
        {#each groups as g (g.id)}
          <section class="shortcuts-group">
            <h3 class="shortcuts-group-title">{g.label}</h3>
            <ul class="shortcuts-list">
              {#each entriesFor(g.id) as entry (entry.keys)}
                <li class="shortcuts-row">
                  <span class="shortcuts-keys">
                    {#each renderKey(entry.keys) as part, i}
                      {#if i > 0 && entry.keys.includes(' / ')}<span class="shortcuts-sep">or</span>{/if}
                      <kbd class="shortcuts-key">{part}</kbd>
                    {/each}
                  </span>
                  <span class="shortcuts-desc">{entry.description}</span>
                </li>
              {/each}
            </ul>
          </section>
        {/each}
      </div>
      <p class="shortcuts-footnote">
        Press <kbd class="shortcuts-key">?</kbd> any time to reopen this list.
        Shortcuts are disabled while typing in inputs or while the composer is open.
      </p>
    </div>
  </div>
{/if}

<style>
  .shortcuts-overlay {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1100;
    padding: var(--space-4);
  }

  .shortcuts-panel {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl, 16px);
    padding: var(--space-6);
    max-width: 720px;
    width: 100%;
    max-height: 90vh;
    max-height: 90dvh;
    overflow: auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .shortcuts-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
  }

  .shortcuts-title {
    margin: 0;
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
  }

  .shortcuts-close {
    background: transparent;
    border: none;
    color: var(--color-text-secondary);
    cursor: pointer;
    border-radius: 9999px;
    width: 32px;
    height: 32px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .shortcuts-close:hover {
    background: var(--color-surface-hover, rgba(0, 0, 0, 0.04));
    color: var(--color-text);
  }

  .shortcuts-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
    gap: var(--space-4);
  }

  .shortcuts-group-title {
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--color-text-secondary);
    margin: 0 0 var(--space-2) 0;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .shortcuts-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .shortcuts-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  .shortcuts-keys {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
  }

  .shortcuts-key {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 24px;
    padding: 2px 8px;
    background: var(--color-surface-container-high, rgba(0, 0, 0, 0.06));
    border: 1px solid var(--color-border);
    border-block-end-width: 2px;
    border-radius: 6px;
    font-family: var(--font-mono, monospace);
    font-size: 0.8125rem;
    color: var(--color-text);
  }

  .shortcuts-sep {
    font-size: 0.75rem;
    color: var(--color-text-tertiary);
    padding: 0 2px;
  }

  .shortcuts-desc {
    color: var(--color-text-secondary);
    text-align: end;
  }

  .shortcuts-footnote {
    margin: 0;
    padding-block-start: var(--space-3);
    border-block-start: 1px solid var(--color-border);
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    line-height: 1.5;
  }
</style>

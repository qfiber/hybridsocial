<script lang="ts">
  let {
    onsend,
    onattach,
    disabled = false
  }: {
    onsend?: (content: string) => void;
    onattach?: () => void;
    disabled?: boolean;
  } = $props();

  let content = $state('');
  let textareaEl: HTMLTextAreaElement | undefined = $state();

  function handleSubmit() {
    const trimmed = content.trim();
    if (!trimmed || disabled) return;
    onsend?.(trimmed);
    content = '';
    if (textareaEl) {
      textareaEl.style.height = 'auto';
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    }
  }

  function autoResize() {
    if (!textareaEl) return;
    textareaEl.style.height = 'auto';
    textareaEl.style.height = Math.min(textareaEl.scrollHeight, 120) + 'px';
  }

  let canSend = $derived(content.trim().length > 0 && !disabled);
</script>

<div class="message-input-bar">
  <button
    type="button"
    class="attach-btn"
    onclick={onattach}
    aria-label="Attach media"
    {disabled}
  >
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48" />
    </svg>
  </button>

  <textarea
    bind:this={textareaEl}
    bind:value={content}
    class="message-textarea"
    placeholder="Write a message..."
    rows="1"
    onkeydown={handleKeydown}
    oninput={autoResize}
    {disabled}
  ></textarea>

  <button
    type="button"
    class="send-btn"
    class:active={canSend}
    onclick={handleSubmit}
    disabled={!canSend}
    aria-label="Send message"
  >
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <line x1="22" y1="2" x2="11" y2="13" />
      <polygon points="22 2 15 22 11 13 2 9 22 2" />
    </svg>
  </button>
</div>

<style>
  .message-input-bar {
    display: flex;
    align-items: flex-end;
    gap: var(--space-2);
    padding: var(--space-3) var(--space-4);
    border-block-start: 1px solid var(--color-border);
    background: var(--color-bg);
  }

  .attach-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border: none;
    background: none;
    border-radius: var(--radius-full);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
    flex-shrink: 0;
  }

  .attach-btn:hover:not(:disabled) {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .attach-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .message-textarea {
    flex: 1;
    padding: var(--space-2) var(--space-3);
    font-size: var(--text-sm);
    line-height: 1.5;
    color: var(--color-text);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    resize: none;
    overflow-y: auto;
    max-height: 120px;
    transition: border-color var(--transition-fast);
  }

  .message-textarea::placeholder {
    color: var(--color-text-tertiary);
  }

  .message-textarea:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .message-textarea:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .send-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border: none;
    background: var(--color-surface);
    border-radius: var(--radius-full);
    color: var(--color-text-tertiary);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
    flex-shrink: 0;
  }

  .send-btn.active {
    background: var(--color-primary);
    color: var(--color-text-on-primary);
  }

  .send-btn:hover:not(:disabled) {
    background: var(--color-primary-hover);
    color: var(--color-text-on-primary);
  }

  .send-btn:disabled {
    cursor: not-allowed;
  }
</style>

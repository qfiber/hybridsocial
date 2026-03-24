<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { uploadMedia } from '$lib/api/media.js';
  import type { Post, MediaAttachment } from '$lib/api/types.js';
  import { currentUser } from '$lib/stores/auth.js';
  import EmojiPicker from './EmojiPicker.svelte';

  let isOpen = $state(false);
  let content = $state('');
  let visibility = $state<'public' | 'followers' | 'direct'>('public');
  let spoilerText = $state('');
  let showCW = $state(false);
  let loading = $state(false);
  let error = $state('');
  let replyTo = $state<Post | null>(null);

  // Tier-aware limits
  let charLimit = $derived($currentUser?.limits?.char_limit ?? 5000);
  let maxMedia = $derived($currentUser?.limits?.media_per_post ?? 4);
  let maxPollOptions = $derived($currentUser?.limits?.poll_options ?? 4);
  let canSchedule = $derived($currentUser?.limits?.scheduled_posts ?? false);
  let textareaEl: HTMLTextAreaElement | undefined = $state();
  let fileInputEl: HTMLInputElement | undefined = $state();

  // Media state
  let uploadedMedia = $state<MediaAttachment[]>([]);
  let mediaUploading = $state(false);

  // Emoji picker state
  let showEmojiPicker = $state(false);

  // Poll state
  let showPoll = $state(false);
  let pollOptions = $state<string[]>(['', '']);
  let pollDuration = $state('86400'); // 1 day in seconds
  let pollMultiple = $state(false);

  const pollDurations = [
    { value: '3600', label: '1 hour' },
    { value: '21600', label: '6 hours' },
    { value: '86400', label: '1 day' },
    { value: '259200', label: '3 days' },
    { value: '604800', label: '7 days' },
  ];

  let charCount = $derived(content.length);
  let charsRemaining = $derived(charLimit - charCount);
  let isOverLimit = $derived(charsRemaining < 0);
  let canSubmit = $derived(
    content.trim().length > 0
    && !isOverLimit
    && !loading
    && !mediaUploading
    && (!showPoll || (pollOptions.filter((o) => o.trim()).length >= 2))
  );

  // Listen for open-composer events (from reply buttons, etc)
  onMount(() => {
    function handleOpenComposer(e: Event) {
      const detail = (e as CustomEvent).detail;
      if (detail?.replyTo) {
        replyTo = detail.replyTo;
      }
      openComposer();
    }

    window.addEventListener('open-composer', handleOpenComposer);
    return () => window.removeEventListener('open-composer', handleOpenComposer);
  });

  function openComposer() {
    isOpen = true;
    // Focus textarea on next tick
    setTimeout(() => textareaEl?.focus(), 50);
  }

  function closeComposer() {
    if (content.trim() && !confirm('Discard your post?')) return;
    resetComposer();
  }

  function resetComposer() {
    isOpen = false;
    content = '';
    spoilerText = '';
    showCW = false;
    replyTo = null;
    error = '';
    uploadedMedia = [];
    showPoll = false;
    pollOptions = ['', ''];
    pollDuration = '86400';
    pollMultiple = false;
  }

  function autoGrow() {
    if (!textareaEl) return;
    textareaEl.style.height = 'auto';
    textareaEl.style.height = textareaEl.scrollHeight + 'px';
  }

  // Media upload
  function triggerFileInput() {
    fileInputEl?.click();
  }

  async function handleFileSelected(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    input.value = '';

    if (uploadedMedia.length >= maxMedia) {
      error = `Maximum ${maxMedia} media attachments allowed`;
      return;
    }

    mediaUploading = true;
    error = '';
    try {
      const attachment = await uploadMedia(file);
      uploadedMedia = [...uploadedMedia, attachment];
    } catch {
      error = 'Failed to upload media. Please try again.';
    } finally {
      mediaUploading = false;
    }
  }

  function removeMedia(id: string) {
    uploadedMedia = uploadedMedia.filter((m) => m.id !== id);
  }

  // Poll helpers
  function addPollOption() {
    if (pollOptions.length < maxPollOptions) {
      pollOptions = [...pollOptions, ''];
    }
  }

  function removePollOption(index: number) {
    if (pollOptions.length > 2) {
      pollOptions = pollOptions.filter((_, i) => i !== index);
    }
  }

  function updatePollOption(index: number, value: string) {
    pollOptions = pollOptions.map((o, i) => (i === index ? value : o));
  }

  function insertEmoji(text: string) {
    if (!textareaEl) {
      content += text;
      return;
    }
    const start = textareaEl.selectionStart;
    const end = textareaEl.selectionEnd;
    content = content.substring(0, start) + text + content.substring(end);
    showEmojiPicker = false;
    // Restore cursor position after the inserted text
    setTimeout(() => {
      if (textareaEl) {
        const newPos = start + text.length;
        textareaEl.selectionStart = newPos;
        textareaEl.selectionEnd = newPos;
        textareaEl.focus();
      }
    }, 0);
  }

  function handleEmojiClickOutside(e: MouseEvent) {
    const target = e.target as HTMLElement;
    if (!target.closest('.emoji-picker-wrapper')) {
      showEmojiPicker = false;
    }
  }

  function togglePoll() {
    showPoll = !showPoll;
    if (showPoll) {
      // Polls and media are mutually exclusive on most platforms
      uploadedMedia = [];
    } else {
      pollOptions = ['', ''];
      pollDuration = '86400';
      pollMultiple = false;
    }
  }

  async function handleSubmit() {
    if (!canSubmit) return;
    loading = true;
    error = '';

    try {
      const body: Record<string, unknown> = {
        content,
        visibility,
      };
      if (showCW && spoilerText) {
        body.spoiler_text = spoilerText;
        body.sensitive = true;
      }
      if (replyTo) {
        body.parent_id = replyTo.id;
      }
      if (uploadedMedia.length > 0) {
        body.media_ids = uploadedMedia.map((m) => m.id);
      }
      if (showPoll) {
        const validOptions = pollOptions.filter((o) => o.trim());
        if (validOptions.length >= 2) {
          const durationSeconds = parseInt(pollDuration, 10);
          const expiresAt = new Date(Date.now() + durationSeconds * 1000).toISOString();
          body.post_type = 'poll';
          body.options = validOptions;
          body.multiple_choice = pollMultiple;
          body.expires_at = expiresAt;
        }
      }

      const newPost = await api.post('/api/v1/statuses', body);
      resetComposer();
      // Notify the timeline to prepend the new post
      window.dispatchEvent(new CustomEvent('new-post', { detail: newPost }));
    } catch {
      error = 'Failed to publish post. Please try again.';
    } finally {
      loading = false;
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    // Ctrl/Cmd + Enter to submit
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault();
      handleSubmit();
    }
    // Escape to close
    if (e.key === 'Escape') {
      closeComposer();
    }
  }

  const visibilityOptions = [
    { value: 'public' as const, label: 'Public', icon: '\u{1F30D}' },
    { value: 'followers' as const, label: 'Followers only', icon: '\u{1F512}' },
    { value: 'direct' as const, label: 'Direct message', icon: '\u{2709}\u{FE0F}' },
  ];
</script>

<!-- Floating action button -->
{#if !isOpen}
  <button
    type="button"
    class="fab"
    onclick={openComposer}
    aria-label="Compose new post"
  >
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <path d="M12 20h9"/>
      <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
    </svg>
  </button>
{/if}

<!-- Composer panel -->
{#if isOpen}
  <div class="composer-backdrop" onclick={closeComposer} role="presentation"></div>
  <div
    class="composer-panel"
    role="dialog"
    aria-label="Compose post"
    aria-modal="true"
    onkeydown={handleKeydown}
    onclick={handleEmojiClickOutside}
  >
    <div class="composer-header">
      <button
        type="button"
        class="composer-close"
        onclick={closeComposer}
        aria-label="Close composer"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <line x1="18" y1="6" x2="6" y2="18"/>
          <line x1="6" y1="6" x2="18" y2="18"/>
        </svg>
      </button>

      <button
        type="button"
        class="composer-submit"
        disabled={!canSubmit}
        onclick={handleSubmit}
      >
        {#if loading}
          <span class="spinner" aria-hidden="true"></span>
          Publishing...
        {:else}
          Publish
        {/if}
      </button>
    </div>

    {#if replyTo}
      <div class="composer-reply-context">
        Replying to <strong>@{replyTo.account.handle}</strong>
      </div>
    {/if}

    {#if error}
      <div class="composer-error" role="alert">{error}</div>
    {/if}

    {#if showCW}
      <input
        type="text"
        class="composer-cw-input"
        placeholder="Content warning"
        bind:value={spoilerText}
        aria-label="Content warning text"
      />
    {/if}

    <textarea
      bind:this={textareaEl}
      bind:value={content}
      oninput={autoGrow}
      class="composer-textarea"
      placeholder="What's on your mind?"
      aria-label="Post content"
      rows={3}
    ></textarea>

    <!-- Media previews -->
    {#if uploadedMedia.length > 0}
      <div class="media-previews">
        {#each uploadedMedia as media (media.id)}
          <div class="media-preview-item">
            {#if media.type === 'image' || media.type === 'gifv'}
              <img src={media.preview_url || media.url} alt={media.description || ''} class="media-preview-img" />
            {:else if media.type === 'video'}
              <div class="media-preview-video">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <polygon points="5 3 19 12 5 21 5 3"/>
                </svg>
              </div>
            {/if}
            <button
              type="button"
              class="media-preview-remove"
              onclick={() => removeMedia(media.id)}
              aria-label="Remove attachment"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
              </svg>
            </button>
          </div>
        {/each}
        {#if mediaUploading}
          <div class="media-preview-item media-preview-loading">
            <span class="spinner" aria-hidden="true"></span>
          </div>
        {/if}
      </div>
    {/if}

    <!-- Poll creation -->
    {#if showPoll}
      <div class="poll-creator">
        <div class="poll-options-list">
          {#each pollOptions as option, i (i)}
            <div class="poll-option-row">
              <input
                type="text"
                class="poll-option-input"
                placeholder="Option {i + 1}"
                value={option}
                oninput={(e) => updatePollOption(i, (e.target as HTMLInputElement).value)}
                aria-label="Poll option {i + 1}"
              />
              {#if pollOptions.length > 2}
                <button
                  type="button"
                  class="poll-option-remove"
                  onclick={() => removePollOption(i)}
                  aria-label="Remove option {i + 1}"
                >
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                  </svg>
                </button>
              {/if}
            </div>
          {/each}
        </div>

        {#if pollOptions.length < maxPollOptions}
          <button type="button" class="poll-add-option" onclick={addPollOption}>
            + Add option
          </button>
        {/if}

        <div class="poll-settings">
          <div class="poll-setting-row">
            <label class="poll-setting-label" for="poll-duration">Duration</label>
            <select id="poll-duration" class="poll-setting-select" bind:value={pollDuration}>
              {#each pollDurations as dur (dur.value)}
                <option value={dur.value}>{dur.label}</option>
              {/each}
            </select>
          </div>

          <label class="poll-setting-toggle">
            <input type="checkbox" bind:checked={pollMultiple} />
            <span>Multiple choice</span>
          </label>
        </div>
      </div>
    {/if}

    <!-- Hidden file input -->
    <input
      bind:this={fileInputEl}
      type="file"
      accept="image/*,video/*"
      class="visually-hidden"
      onchange={handleFileSelected}
    />

    <div class="composer-toolbar">
      <div class="composer-tools">
        <!-- Media button -->
        <button
          type="button"
          class="tool-btn"
          class:tool-active={uploadedMedia.length > 0}
          onclick={triggerFileInput}
          aria-label="Attach media"
          disabled={showPoll || mediaUploading}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/>
          </svg>
        </button>

        <!-- Poll toggle -->
        <button
          type="button"
          class="tool-btn"
          class:tool-active={showPoll}
          onclick={togglePoll}
          aria-label="Add poll"
          aria-pressed={showPoll}
          disabled={uploadedMedia.length > 0}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <rect x="3" y="3" width="7" height="5" rx="1"/><rect x="3" y="10" width="14" height="5" rx="1"/><rect x="3" y="17" width="10" height="5" rx="1"/>
          </svg>
        </button>

        <!-- CW toggle -->
        <button
          type="button"
          class="tool-btn"
          class:tool-active={showCW}
          onclick={() => { showCW = !showCW; }}
          aria-label="Toggle content warning"
          aria-pressed={showCW}
        >
          CW
        </button>

        <!-- Emoji picker -->
        <div class="emoji-picker-wrapper">
          <button
            type="button"
            class="tool-btn"
            class:tool-active={showEmojiPicker}
            onclick={() => { showEmojiPicker = !showEmojiPicker; }}
            aria-label="Insert emoji"
            aria-expanded={showEmojiPicker}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/>
            </svg>
          </button>
          {#if showEmojiPicker}
            <EmojiPicker onselect={insertEmoji} />
          {/if}
        </div>

        <!-- Visibility selector -->
        <select
          class="visibility-select"
          bind:value={visibility}
          aria-label="Post visibility"
        >
          {#each visibilityOptions as opt (opt.value)}
            <option value={opt.value}>{opt.icon} {opt.label}</option>
          {/each}
        </select>
      </div>

      <div class="composer-char-count" class:over-limit={isOverLimit}>
        {charsRemaining}
      </div>
    </div>
  </div>
{/if}

<style>
  .visually-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }

  .fab {
    position: fixed;
    inset-block-end: var(--space-6);
    inset-inline-end: var(--space-6);
    width: 56px;
    height: 56px;
    border-radius: var(--radius-full);
    background: linear-gradient(135deg, var(--color-primary), #0d9488);
    color: var(--color-text-inverse);
    border: none;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: var(--shadow-xl);
    transition: transform var(--transition-fast), box-shadow var(--transition-fast);
    z-index: var(--z-sticky);
  }

  .fab:hover {
    transform: scale(1.05);
    box-shadow: var(--shadow-xl), 0 0 20px rgba(13, 148, 136, 0.3);
  }

  .fab:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 3px;
  }

  .composer-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.3);
    z-index: var(--z-modal-backdrop);
    animation: fade-in 0.15s ease;
  }

  @keyframes fade-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .composer-panel {
    position: fixed;
    inset-block-end: 0;
    inset-inline-start: 0;
    inset-inline-end: 0;
    max-height: 80vh;
    background: var(--color-surface);
    border-start-start-radius: var(--radius-xl);
    border-start-end-radius: var(--radius-xl);
    padding: var(--space-4);
    box-shadow: var(--shadow-xl);
    z-index: var(--z-modal);
    overflow-y: auto;
    animation: slide-up 0.25s ease;
  }

  @keyframes slide-up {
    from {
      transform: translateY(100%);
    }
    to {
      transform: translateY(0);
    }
  }

  @media (min-width: 640px) {
    .composer-panel {
      inset-inline-start: 50%;
      inset-inline-end: auto;
      transform: translateX(-50%);
      inset-block-end: var(--space-8);
      max-width: 560px;
      width: 100%;
      border-radius: var(--radius-xl);
      animation: pop-in 0.2s ease;
    }

    @keyframes pop-in {
      from {
        opacity: 0;
        transform: translateX(-50%) scale(0.95);
      }
      to {
        opacity: 1;
        transform: translateX(-50%) scale(1);
      }
    }
  }

  .composer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-3);
  }

  .composer-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    background: transparent;
    border: none;
    border-radius: var(--radius-full);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background-color var(--transition-fast);
  }

  .composer-close:hover {
    background: var(--color-bg-tertiary);
  }

  .composer-submit {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-4);
    background: var(--color-primary);
    color: var(--color-text-inverse);
    border: none;
    border-radius: var(--radius-full);
    font-size: var(--text-sm);
    font-weight: var(--font-semibold);
    cursor: pointer;
    transition: background-color var(--transition-fast);
  }

  .composer-submit:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .composer-submit:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .composer-reply-context {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    padding: var(--space-2) var(--space-3);
    background: var(--color-bg-tertiary);
    border-radius: var(--radius-md);
    margin-block-end: var(--space-3);
  }

  .composer-error {
    font-size: var(--text-sm);
    color: var(--color-danger);
    padding: var(--space-2) var(--space-3);
    background: var(--color-danger-light);
    border-radius: var(--radius-md);
    margin-block-end: var(--space-3);
  }

  .composer-cw-input {
    display: block;
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-warning);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-warning-light);
    margin-block-end: var(--space-2);
  }

  .composer-cw-input:focus {
    outline: none;
    box-shadow: 0 0 0 2px var(--color-warning);
  }

  .composer-textarea {
    display: block;
    width: 100%;
    min-height: 100px;
    max-height: 40vh;
    padding: var(--space-3);
    border: none;
    font-size: var(--text-base);
    color: var(--color-text);
    background: transparent;
    resize: none;
    line-height: var(--leading-relaxed);
  }

  .composer-textarea::placeholder {
    color: var(--color-text-tertiary);
  }

  .composer-textarea:focus {
    outline: none;
  }

  /* Media previews */
  .media-previews {
    display: flex;
    gap: var(--space-2);
    flex-wrap: wrap;
    padding: var(--space-2) var(--space-3);
  }

  .media-preview-item {
    position: relative;
    width: 80px;
    height: 80px;
    border-radius: var(--radius-md);
    overflow: hidden;
    background: var(--color-bg-tertiary);
  }

  .media-preview-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .media-preview-video {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--color-text-secondary);
  }

  .media-preview-loading {
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .media-preview-remove {
    position: absolute;
    inset-block-start: 2px;
    inset-inline-end: 2px;
    width: 22px;
    height: 22px;
    border-radius: var(--radius-full);
    background: rgba(0, 0, 0, 0.6);
    color: white;
    border: none;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .media-preview-remove:hover {
    background: rgba(0, 0, 0, 0.8);
  }

  /* Poll creator */
  .poll-creator {
    padding: var(--space-3);
    margin: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .poll-options-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .poll-option-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .poll-option-input {
    flex: 1;
    padding: var(--space-2);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-bg);
  }

  .poll-option-input:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .poll-option-remove {
    width: 28px;
    height: 28px;
    flex-shrink: 0;
    border: none;
    background: transparent;
    color: var(--color-text-tertiary);
    cursor: pointer;
    border-radius: var(--radius-full);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .poll-option-remove:hover {
    background: var(--color-bg-tertiary);
    color: var(--color-danger);
  }

  .poll-add-option {
    align-self: flex-start;
    padding: var(--space-1) var(--space-2);
    border: 1px dashed var(--color-border);
    border-radius: var(--radius-md);
    background: transparent;
    color: var(--color-primary);
    font-size: var(--text-sm);
    cursor: pointer;
  }

  .poll-add-option:hover {
    background: var(--color-bg-tertiary);
  }

  .poll-settings {
    display: flex;
    align-items: center;
    gap: var(--space-4);
    flex-wrap: wrap;
    padding-block-start: var(--space-2);
    border-block-start: 1px solid var(--color-border);
  }

  .poll-setting-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .poll-setting-label {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .poll-setting-select {
    padding: var(--space-1) var(--space-2);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    background: var(--color-bg);
  }

  .poll-setting-toggle {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    cursor: pointer;
  }

  .poll-setting-toggle input {
    accent-color: var(--color-primary);
  }

  .composer-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-block-start: var(--space-3);
    border-block-start: 1px solid var(--color-border);
  }

  .composer-tools {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .tool-btn {
    padding: var(--space-1) var(--space-2);
    background: transparent;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-xs);
    font-weight: var(--font-semibold);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background-color var(--transition-fast), border-color var(--transition-fast);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-1);
  }

  .tool-btn:hover:not(:disabled) {
    background: var(--color-bg-tertiary);
  }

  .tool-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .tool-active {
    background: var(--color-warning-light);
    border-color: var(--color-warning);
    color: var(--color-warning);
  }

  .emoji-picker-wrapper {
    position: relative;
  }

  .visibility-select {
    padding: var(--space-1) var(--space-2);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    background: var(--color-bg);
    cursor: pointer;
  }

  .visibility-select:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .composer-char-count {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    font-variant-numeric: tabular-nums;
  }

  .over-limit {
    color: var(--color-danger);
    font-weight: var(--font-semibold);
  }

  .spinner {
    display: inline-block;
    width: 14px;
    height: 14px;
    border: 2px solid currentColor;
    border-inline-end-color: transparent;
    border-radius: var(--radius-full);
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>

<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { uploadMedia } from '$lib/api/media.js';
  import { search } from '$lib/api/search.js';
  import type { Post, MediaAttachment, Identity } from '$lib/api/types.js';
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

  // --- Mention autocomplete ---
  let mentionSuggestions = $state<Identity[]>([]);
  let mentionActive = $state(false);
  let mentionIndex = $state(0);
  let mentionQuery = $state('');
  let mentionAtPos = $state(0);
  let mentionDebounce: ReturnType<typeof setTimeout> | null = null;

  function handleTextareaInput() {
    autoGrow();
    detectMention();
  }

  function detectMention() {
    if (!textareaEl) return;
    const cursor = textareaEl.selectionStart;
    const text = content.substring(0, cursor);

    // Find the last @ that isn't preceded by a word char
    const match = text.match(/(^|[\s\n])@([a-zA-Z0-9_@.]*)$/);
    if (match) {
      const query = match[2];
      mentionAtPos = cursor - query.length;
      mentionQuery = query;

      if (query.length >= 1) {
        if (mentionDebounce) clearTimeout(mentionDebounce);
        mentionDebounce = setTimeout(() => fetchMentionSuggestions(query), 200);
      } else {
        mentionSuggestions = [];
        mentionActive = false;
      }
    } else {
      closeMentions();
    }
  }

  async function fetchMentionSuggestions(query: string) {
    try {
      const results = await search(query, { type: 'accounts', limit: 4, resolve: true });
      mentionSuggestions = results.accounts || [];
      mentionActive = mentionSuggestions.length > 0;
      mentionIndex = 0;
    } catch {
      mentionSuggestions = [];
      mentionActive = false;
    }
  }

  function selectMention(account: Identity) {
    if (!textareaEl) return;
    const cursor = textareaEl.selectionStart;
    // Replace from @ to current cursor with the full mention
    const before = content.substring(0, mentionAtPos);
    const after = content.substring(cursor);
    const mentionText = account.handle.includes('@')
      ? `${account.handle} `
      : `${account.handle} `;
    content = before + mentionText + after;
    closeMentions();
    setTimeout(() => {
      if (textareaEl) {
        const newPos = mentionAtPos + mentionText.length;
        textareaEl.selectionStart = newPos;
        textareaEl.selectionEnd = newPos;
        textareaEl.focus();
      }
    }, 0);
  }

  function handleMentionKeydown(e: KeyboardEvent) {
    if (!mentionActive) return;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      mentionIndex = (mentionIndex + 1) % mentionSuggestions.length;
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      mentionIndex = (mentionIndex - 1 + mentionSuggestions.length) % mentionSuggestions.length;
    } else if (e.key === 'Enter' || e.key === 'Tab') {
      if (mentionSuggestions.length > 0) {
        e.preventDefault();
        selectMention(mentionSuggestions[mentionIndex]);
      }
    } else if (e.key === 'Escape') {
      e.preventDefault();
      closeMentions();
    }
  }

  function closeMentions() {
    mentionActive = false;
    mentionSuggestions = [];
    mentionQuery = '';
    if (mentionDebounce) clearTimeout(mentionDebounce);
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
    <span class="material-symbols-outlined fab-icon">edit</span>
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
    {#if replyTo}
      <div class="composer-reply-context">
        Replying to <strong>@{replyTo.account.handle}</strong>
      </div>
    {/if}

    {#if error}
      <div class="composer-error" role="alert">{error}</div>
    {/if}

    <div class="composer-body">
      <!-- Avatar -->
      <div class="composer-avatar">
        {#if $currentUser?.avatar_url}
          <img src={$currentUser.avatar_url} alt="" class="composer-avatar-img" />
        {:else}
          <div class="composer-avatar-placeholder" aria-hidden="true">
            {($currentUser?.display_name || $currentUser?.handle || 'U').charAt(0).toUpperCase()}
          </div>
        {/if}
      </div>

      <!-- Text area -->
      <div class="composer-input-area">
        {#if showCW}
          <input
            type="text"
            class="composer-cw-input"
            placeholder="Content warning"
            bind:value={spoilerText}
            aria-label="Content warning text"
          />
        {/if}

        <div class="textarea-wrapper">
          <textarea
            bind:this={textareaEl}
            bind:value={content}
            oninput={handleTextareaInput}
            onkeydown={handleMentionKeydown}
            class="composer-textarea"
            placeholder="What's on your mind?"
            aria-label="Post content"
            rows={3}
          ></textarea>

          {#if mentionActive && mentionSuggestions.length > 0}
            <div class="mention-dropdown" role="listbox" aria-label="Mention suggestions">
              {#each mentionSuggestions as account, i (account.id)}
                <button
                  type="button"
                  class="mention-item"
                  class:mention-item-active={i === mentionIndex}
                  role="option"
                  aria-selected={i === mentionIndex}
                  onclick={() => selectMention(account)}
                  onmouseenter={() => mentionIndex = i}
                >
                  {#if account.avatar_url}
                    <img src={account.avatar_url} alt="" class="mention-avatar" loading="lazy" />
                  {:else}
                    <div class="mention-avatar-placeholder">{(account.display_name || account.handle).charAt(0).toUpperCase()}</div>
                  {/if}
                  <div class="mention-info">
                    <span class="mention-name">{account.display_name || account.handle}</span>
                    <span class="mention-handle">@{account.handle}</span>
                  </div>
                </button>
              {/each}
            </div>
          {/if}
        </div>
      </div>
    </div>

    <!-- Media previews -->
    {#if uploadedMedia.length > 0}
      <div class="media-previews">
        {#each uploadedMedia as media (media.id)}
          <div class="media-preview-item">
            {#if media.type === 'image' || media.type === 'gifv'}
              <img src={media.preview_url || media.url} alt={media.description || ''} class="media-preview-img" />
            {:else if media.type === 'video'}
              <div class="media-preview-video">
                <span class="material-symbols-outlined">play_arrow</span>
              </div>
            {/if}
            <button
              type="button"
              class="media-preview-remove"
              onclick={() => removeMedia(media.id)}
              aria-label="Remove attachment"
            >
              <span class="material-symbols-outlined remove-icon">close</span>
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
                  <span class="material-symbols-outlined remove-icon">close</span>
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

    <!-- Bottom toolbar -->
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
          <span class="material-symbols-outlined tool-icon">image</span>
        </button>

        <!-- GIF button -->
        <button
          type="button"
          class="tool-btn"
          aria-label="Insert GIF"
          disabled
        >
          <span class="material-symbols-outlined tool-icon">gif_box</span>
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
          <span class="material-symbols-outlined tool-icon">ballot</span>
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
            <span class="material-symbols-outlined tool-icon">mood</span>
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

        <!-- CW toggle -->
        <button
          type="button"
          class="tool-btn tool-btn-text"
          class:tool-active={showCW}
          onclick={() => { showCW = !showCW; }}
          aria-label="Toggle content warning"
          aria-pressed={showCW}
        >
          CW
        </button>
      </div>

      <div class="composer-right">
        <span class="composer-char-count" class:over-limit={isOverLimit}>{charsRemaining}</span>
        <button
          type="button"
          class="composer-submit"
          disabled={!canSubmit}
          onclick={handleSubmit}
        >
          {#if loading}
            <span class="spinner" aria-hidden="true"></span>
            Posting...
          {:else}
            Post
          {/if}
        </button>
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

  /* ---- FAB ---- */
  .fab {
    position: fixed;
    inset-block-end: 24px;
    inset-inline-end: 24px;
    width: 56px;
    height: 56px;
    border-radius: 9999px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    border: none;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 4px 16px rgba(0, 106, 105, 0.3);
    transition: transform 150ms ease, box-shadow 150ms ease;
    z-index: var(--z-sticky);
  }

  .fab:hover {
    transform: scale(1.05);
    box-shadow: 0 6px 24px rgba(0, 106, 105, 0.4);
  }

  .fab:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 3px;
  }

  .fab-icon {
    font-size: 24px;
  }

  /* ---- Backdrop ---- */
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

  /* ---- Composer Card ---- */
  .composer-panel {
    position: fixed;
    inset-block-end: 0;
    inset-inline-start: 0;
    inset-inline-end: 0;
    max-height: 80vh;
    background: var(--color-surface-container-lowest);
    border-start-start-radius: 18px;
    border-start-end-radius: 18px;
    padding: 24px;
    box-shadow: 0 -4px 24px rgba(0, 0, 0, 0.08);
    z-index: var(--z-modal);
    overflow-y: auto;
    animation: slide-up 0.25s ease;
  }

  @keyframes slide-up {
    from { transform: translateY(100%); }
    to { transform: translateY(0); }
  }

  @media (min-width: 640px) {
    .composer-panel {
      inset-inline-start: 50%;
      inset-inline-end: auto;
      transform: translateX(-50%);
      inset-block-end: var(--space-8);
      max-width: 560px;
      width: 100%;
      border-radius: 14px;
      border: 1px solid var(--color-border);
      animation: pop-in 0.2s ease;
    }

    @keyframes pop-in {
      from { opacity: 0; transform: translateX(-50%) scale(0.95); }
      to { opacity: 1; transform: translateX(-50%) scale(1); }
    }
  }

  /* ---- Reply context ---- */
  .composer-reply-context {
    font-size: 0.875rem;
    color: var(--color-text-secondary);
    padding: 8px 12px;
    background: var(--color-surface);
    border-radius: 10px;
    margin-block-end: 16px;
  }

  .composer-error {
    font-size: 0.875rem;
    color: var(--color-danger);
    padding: 8px 12px;
    background: var(--color-danger-soft);
    border-radius: 10px;
    margin-block-end: 16px;
  }

  /* ---- Composer Body (avatar + textarea) ---- */
  .composer-body {
    display: flex;
    gap: 16px;
  }

  .composer-avatar {
    flex-shrink: 0;
  }

  .composer-avatar-img {
    width: 48px;
    height: 48px;
    border-radius: 9999px;
    object-fit: cover;
  }

  .composer-avatar-placeholder {
    width: 48px;
    height: 48px;
    border-radius: 9999px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 1rem;
  }

  .composer-input-area {
    flex: 1;
    min-width: 0;
  }

  .composer-cw-input {
    display: block;
    width: 100%;
    padding: 8px 0;
    border: none;
    border-block-end: 1px solid var(--color-warning);
    font-size: 0.875rem;
    color: var(--color-text);
    background: transparent;
    margin-block-end: 4px;
  }

  .composer-cw-input::placeholder {
    color: var(--color-warning);
    opacity: 0.7;
  }

  .composer-cw-input:focus {
    outline: none;
  }

  .composer-textarea {
    display: block;
    width: 100%;
    min-height: 100px;
    max-height: 40vh;
    padding: 4px 0;
    border: none;
    font-size: 1.125rem;
    color: var(--color-text);
    background: transparent;
    resize: none;
    line-height: 1.6;
  }

  .composer-textarea::placeholder {
    color: var(--color-text-tertiary);
    opacity: 0.5;
  }

  .composer-textarea:focus {
    outline: none;
  }

  /* ---- Media Previews ---- */
  .media-previews {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    padding: 8px 0;
    margin-inline-start: 64px;
  }

  .media-preview-item {
    position: relative;
    width: 80px;
    height: 80px;
    border-radius: 10px;
    overflow: hidden;
    background: var(--color-surface);
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
    inset-block-start: 4px;
    inset-inline-end: 4px;
    width: 22px;
    height: 22px;
    border-radius: 9999px;
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

  .remove-icon {
    font-size: 14px;
  }

  /* ---- Poll Creator ---- */
  .poll-creator {
    padding: 12px;
    margin: 8px 0;
    margin-inline-start: 64px;
    border: 1px solid var(--color-border);
    border-radius: 12px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .poll-options-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .poll-option-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .poll-option-input {
    flex: 1;
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
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
    border-radius: 9999px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .poll-option-remove:hover {
    background: var(--color-surface);
    color: var(--color-danger);
  }

  .poll-add-option {
    align-self: flex-start;
    padding: 4px 12px;
    border: 1px dashed var(--color-border);
    border-radius: 9999px;
    background: transparent;
    color: var(--color-primary);
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
  }

  .poll-add-option:hover {
    background: var(--color-surface);
  }

  .poll-settings {
    display: flex;
    align-items: center;
    gap: 16px;
    flex-wrap: wrap;
    padding-block-start: 8px;
    border-block-start: 1px solid var(--color-border);
  }

  .poll-setting-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .poll-setting-label {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .poll-setting-select {
    padding: 4px 8px;
    border: 1px solid var(--color-border);
    border-radius: 8px;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    background: var(--color-surface-container-lowest);
  }

  .poll-setting-toggle {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    cursor: pointer;
  }

  .poll-setting-toggle input {
    accent-color: var(--color-primary);
  }

  /* ---- Bottom Toolbar ---- */
  .composer-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-block-start: 16px;
    margin-block-start: 8px;
    border-block-start: 1px solid var(--color-border);
  }

  .composer-tools {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .tool-btn {
    width: 36px;
    height: 36px;
    background: transparent;
    border: none;
    border-radius: 9999px;
    color: var(--color-primary);
    cursor: pointer;
    transition: background-color 150ms ease;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .tool-btn:hover:not(:disabled) {
    background: rgba(191, 235, 233, 0.3);
  }

  .tool-btn:disabled {
    opacity: 0.35;
    cursor: not-allowed;
  }

  .tool-active {
    background: rgba(191, 235, 233, 0.3);
  }

  .tool-icon {
    font-size: 22px;
  }

  .tool-btn-text {
    width: auto;
    padding: 0 10px;
    font-size: var(--text-xs);
    font-weight: 700;
  }

  .emoji-picker-wrapper {
    position: relative;
  }

  .visibility-select {
    padding: 4px 8px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    background: var(--color-surface-container-lowest);
    cursor: pointer;
  }

  .visibility-select:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .composer-right {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .composer-char-count {
    font-size: 0.875rem;
    color: var(--color-text-tertiary);
    font-variant-numeric: tabular-nums;
  }

  .over-limit {
    color: var(--color-danger);
    font-weight: 700;
  }

  .composer-submit {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 8px 32px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 700;
    cursor: pointer;
    transition: background-color 150ms ease;
  }

  .composer-submit:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .composer-submit:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .spinner {
    display: inline-block;
    width: 14px;
    height: 14px;
    border: 2px solid currentColor;
    border-inline-end-color: transparent;
    border-radius: 9999px;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  /* --- Mention autocomplete --- */
  .textarea-wrapper {
    position: relative;
    flex: 1;
  }

  .mention-dropdown {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 100%;
    margin-bottom: 4px;
    background: var(--color-surface-container-lowest, #fff);
    border: 1px solid rgba(188, 201, 200, 0.25);
    border-radius: 12px;
    box-shadow: 0 4px 16px rgba(25, 28, 29, 0.1);
    overflow: hidden;
    z-index: 20;
  }

  .mention-item {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 10px 14px;
    border: none;
    background: transparent;
    cursor: pointer;
    text-align: start;
    transition: background 100ms ease;
  }

  .mention-item:hover,
  .mention-item-active {
    background: var(--color-surface-container-low, #f2f4f5);
  }

  .mention-avatar {
    width: 32px;
    height: 32px;
    border-radius: 9999px;
    object-fit: cover;
    flex-shrink: 0;
  }

  .mention-avatar-placeholder {
    width: 32px;
    height: 32px;
    border-radius: 9999px;
    background: var(--color-primary, #006a69);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 0.8rem;
    flex-shrink: 0;
  }

  .mention-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .mention-name {
    font-weight: 600;
    font-size: 0.875rem;
    color: var(--color-text, #191c1d);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .mention-handle {
    font-size: 0.75rem;
    color: var(--color-text-secondary, #3d4949);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>

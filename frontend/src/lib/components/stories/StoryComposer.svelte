<script lang="ts">
  import { uploadMedia } from '$lib/api/media.js';
  import { createStory, type StoryDuration } from '$lib/api/stories.js';

  let {
    onclose,
    oncreated,
  }: {
    onclose: () => void;
    oncreated: () => void;
  } = $props();

  let fileInput: HTMLInputElement | null = $state(null);
  let selectedFile: File | null = $state(null);
  let previewUrl: string | null = $state(null);
  let isVideo = $state(false);

  let caption = $state('');
  let duration: StoryDuration = $state(24);
  let submitting = $state(false);
  let error: string | null = $state(null);

  const DURATIONS: StoryDuration[] = [8, 16, 24];

  function handleFileChange(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    if (!file.type.startsWith('image/') && !file.type.startsWith('video/')) {
      error = 'Please choose an image or video';
      return;
    }
    error = null;
    selectedFile = file;
    isVideo = file.type.startsWith('video/');
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    previewUrl = URL.createObjectURL(file);
  }

  function clearFile() {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    previewUrl = null;
    selectedFile = null;
    if (fileInput) fileInput.value = '';
  }

  async function submit() {
    if (!selectedFile || submitting) return;
    submitting = true;
    error = null;

    try {
      const media = await uploadMedia(selectedFile);
      await createStory({
        media_id: (media as { id: string }).id,
        caption: caption.trim() || undefined,
        duration_hours: duration,
      });

      window.dispatchEvent(new CustomEvent('story-created'));
      oncreated();
    } catch (err) {
      error = (err as Error).message || 'Failed to create story';
    } finally {
      submitting = false;
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape' && !submitting) onclose();
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="overlay" role="dialog" aria-modal="true" aria-label="Create story">
  <div class="composer">
    <div class="header">
      <button type="button" class="icon-btn" onclick={onclose} aria-label="Close" disabled={submitting}>
        <span class="material-symbols-outlined">close</span>
      </button>
      <div class="title">New story</div>
      <button
        type="button"
        class="post-btn"
        onclick={submit}
        disabled={!selectedFile || submitting}
      >
        {submitting ? 'Posting…' : 'Post'}
      </button>
    </div>

    <div class="preview">
      {#if !previewUrl}
        <button type="button" class="picker" onclick={() => fileInput?.click()}>
          <span class="material-symbols-outlined picker-icon">add_photo_alternate</span>
          <div class="picker-label">Choose photo or video</div>
          <div class="picker-hint">Image or video, max per your tier</div>
        </button>
      {:else}
        <div class="media-wrapper">
          {#if isVideo}
            <video src={previewUrl} controls playsinline></video>
          {:else}
            <img src={previewUrl} alt="" />
          {/if}
          {#if caption}
            <div class="caption-overlay">{caption}</div>
          {/if}
          <button type="button" class="clear-btn" onclick={clearFile} aria-label="Remove file">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>
      {/if}
      <input
        bind:this={fileInput}
        type="file"
        accept="image/*,video/*"
        hidden
        onchange={handleFileChange}
      />
    </div>

    <div class="controls">
      <div class="field">
        <label for="story-caption">Caption</label>
        <input
          id="story-caption"
          type="text"
          maxlength="200"
          bind:value={caption}
          placeholder="Add a caption (optional)"
          disabled={submitting}
        />
        <div class="char-count">{caption.length}/200</div>
      </div>

      <div class="field">
        <span class="label">Duration</span>
        <div class="duration-options">
          {#each DURATIONS as h}
            <button
              type="button"
              class="duration-btn"
              class:active={duration === h}
              onclick={() => (duration = h)}
              disabled={submitting}
            >
              {h}h
            </button>
          {/each}
        </div>
      </div>

      {#if error}
        <div class="error">{error}</div>
      {/if}
    </div>
  </div>
</div>

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.7);
    z-index: 1050;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 16px;
  }

  .composer {
    width: 100%;
    max-width: 480px;
    max-height: 90vh;
    max-height: 90dvh;
    background: var(--color-surface);
    border-radius: 16px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 14px;
    border-bottom: 1px solid var(--color-border);
  }

  .title {
    font-weight: 600;
    color: var(--color-text);
  }

  .icon-btn {
    background: transparent;
    border: none;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    color: var(--color-text);
  }

  .icon-btn:hover:not(:disabled) {
    background: var(--color-surface-container);
  }

  .icon-btn:disabled { opacity: 0.5; cursor: not-allowed; }

  .post-btn {
    background: var(--color-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: 999px;
    padding: 8px 18px;
    font-weight: 600;
    cursor: pointer;
    font-size: 0.875rem;
  }

  .post-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .preview {
    background: var(--color-surface-container);
    aspect-ratio: 9 / 16;
    max-height: 50vh;
    max-height: 50dvh;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;
  }

  .picker {
    width: 100%;
    height: 100%;
    background: transparent;
    border: 2px dashed var(--color-border);
    border-radius: 0;
    color: var(--color-text-secondary);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    cursor: pointer;
  }

  .picker:hover {
    border-color: var(--color-primary);
    color: var(--color-text);
  }

  .picker-icon {
    font-size: 56px;
  }

  .picker-label {
    font-weight: 600;
  }

  .picker-hint {
    font-size: 0.75rem;
    opacity: 0.7;
  }

  .media-wrapper {
    width: 100%;
    height: 100%;
    position: relative;
    background: #000;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .media-wrapper img,
  .media-wrapper video {
    max-width: 100%;
    max-height: 100%;
    object-fit: contain;
  }

  .caption-overlay {
    position: absolute;
    left: 16px;
    right: 16px;
    bottom: 24px;
    color: white;
    font-size: 1rem;
    text-align: center;
    text-shadow: 0 2px 6px rgba(0,0,0,0.8);
    padding: 8px 12px;
    background: var(--scrim-medium);
    border-radius: 10px;
    backdrop-filter: blur(4px);
  }

  .clear-btn {
    position: absolute;
    top: 8px;
    right: 8px;
    width: 32px;
    height: 32px;
    border-radius: 50%;
    background: var(--scrim-medium);
    border: none;
    color: white;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .clear-btn .material-symbols-outlined {
    font-size: 18px;
  }

  .controls {
    padding: 14px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 6px;
    position: relative;
  }

  .field label,
  .field .label {
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.4px;
  }

  .field input {
    background: var(--color-surface-container);
    border: 1px solid var(--color-border);
    border-radius: 10px;
    padding: 10px 12px;
    color: var(--color-text);
    font-size: 0.9rem;
  }

  .field input:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .char-count {
    position: absolute;
    right: 8px;
    bottom: 8px;
    font-size: 0.7rem;
    color: var(--color-text-secondary);
    pointer-events: none;
  }

  .duration-options {
    display: flex;
    gap: 8px;
  }

  .duration-btn {
    flex: 1;
    padding: 10px;
    background: var(--color-surface-container);
    border: 1px solid var(--color-border);
    border-radius: 10px;
    color: var(--color-text);
    font-weight: 600;
    cursor: pointer;
    transition: all 150ms ease;
  }

  .duration-btn:hover:not(:disabled) {
    border-color: var(--color-primary);
  }

  .duration-btn.active {
    background: var(--color-primary);
    color: var(--color-on-primary);
    border-color: var(--color-primary);
  }

  .duration-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .error {
    color: var(--color-error, #d32f2f);
    font-size: 0.85rem;
    background: var(--color-error-container, rgba(211, 47, 47, 0.1));
    padding: 8px 12px;
    border-radius: 8px;
  }
</style>

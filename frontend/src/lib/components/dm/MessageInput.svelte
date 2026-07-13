<script lang="ts">
  import { onDestroy } from 'svelte';
  import { uploadMedia } from '$lib/api/media.js';
  import type { MediaAttachment } from '$lib/api/types.js';
  import { addToast } from '$lib/stores/toast.js';
  import { currentUser } from '$lib/stores/auth.js';
  import EmojiPicker from '$lib/components/post/EmojiPicker.svelte';

  let {
    onsend,
    disabled = false,
    // DMs currently store one media per message (single belongs_to on
    // the Message schema). Until a join-table refactor lands, cap to 1
    // here so the user doesn't queue four attachments only to silently
    // lose three on send.
    maxAttachments = 1,
    replyingTo = null,
    oncancelreply,
    ontyping,
  }: {
    onsend?: (content: string, mediaIds: string[], replyToId: string | null) => void;
    disabled?: boolean;
    maxAttachments?: number;
    replyingTo?: import('$lib/api/types.js').Message | null;
    oncancelreply?: () => void;
    ontyping?: () => void;
  } = $props();

  // Same gate as PostComposer — reject types up front so we don't
  // ship an unsupported upload to the server only to have it 4xx.
  const ACCEPTED_MIME_TYPES = new Set([
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'video/mp4',
    'video/webm',
    'audio/mpeg',
    'audio/wav',
    'audio/x-wav',
    'audio/ogg',
    'audio/flac',
    'audio/aac',
    'audio/mp4',
    'audio/webm',
  ]);
  const ACCEPTED_EXTENSIONS = new Set([
    '.jpg', '.jpeg', '.png', '.gif', '.webp',
    '.mp4', '.webm',
    '.mp3', '.wav', '.ogg', '.oga', '.opus', '.flac', '.aac', '.m4a', '.weba',
  ]);
  const ACCEPT_ATTR = [...ACCEPTED_MIME_TYPES, ...ACCEPTED_EXTENSIONS].join(',');

  function isAcceptedFile(f: File): boolean {
    if (f.type && ACCEPTED_MIME_TYPES.has(f.type)) return true;
    const dot = f.name.lastIndexOf('.');
    if (dot < 0) return false;
    return ACCEPTED_EXTENSIONS.has(f.name.slice(dot).toLowerCase());
  }

  let content = $state('');
  let textareaEl: HTMLTextAreaElement | undefined = $state();
  let fileInputEl: HTMLInputElement | undefined = $state();
  let uploaded = $state<MediaAttachment[]>([]);
  let uploadingCount = $state(0);
  let showEmoji = $state(false);
  let emojiBtnEl = $state<HTMLButtonElement | undefined>();

  // Insert an emoji at the caret (mirrors the composer). Closes the picker,
  // restores the caret and re-grows the textarea.
  function insertEmoji(text: string) {
    if (!textareaEl) {
      content += text;
      showEmoji = false;
      return;
    }
    const start = textareaEl.selectionStart;
    const end = textareaEl.selectionEnd;
    content = content.substring(0, start) + text + content.substring(end);
    showEmoji = false;
    setTimeout(() => {
      if (!textareaEl) return;
      const pos = start + text.length;
      textareaEl.selectionStart = pos;
      textareaEl.selectionEnd = pos;
      textareaEl.focus();
      autoResize();
    }, 0);
  }

  function triggerFileInput() {
    if (disabled) return;
    fileInputEl?.click();
  }

  async function handleFileSelected(e: Event) {
    const input = e.target as HTMLInputElement;
    const files = Array.from(input.files ?? []);
    // Reset value so picking the same file twice in a row still fires
    // the change event.
    input.value = '';
    if (files.length === 0) return;
    await uploadFiles(files);
  }

  async function uploadFiles(files: File[]) {
    const accepted = files.filter(isAcceptedFile);
    const rejected = files.length - accepted.length;
    if (rejected > 0) {
      addToast(`${rejected} file${rejected === 1 ? '' : 's'} skipped — unsupported type`, 'error');
    }
    const remaining = maxAttachments - uploaded.length - uploadingCount;
    const toUpload = accepted.slice(0, Math.max(0, remaining));
    if (accepted.length > toUpload.length) {
      addToast(`Maximum ${maxAttachments} attachments per message`, 'error');
    }
    if (toUpload.length === 0) return;

    uploadingCount += toUpload.length;
    try {
      const results = await Promise.allSettled(toUpload.map((f) => uploadMedia(f)));
      for (const r of results) {
        if (r.status === 'fulfilled') {
          uploaded = [...uploaded, r.value];
        } else {
          addToast('An attachment failed to upload', 'error');
        }
      }
    } finally {
      uploadingCount = Math.max(0, uploadingCount - toUpload.length);
    }
  }

  function removeAttachment(id: string) {
    uploaded = uploaded.filter((m) => m.id !== id);
  }

  // --- Voice messages ---------------------------------------------------
  // Record audio in the browser and hand the blob to the same upload path as
  // any other attachment — the DM media pipeline already accepts audio, so no
  // backend change is needed.
  const canRecord =
    typeof navigator !== 'undefined' &&
    !!navigator.mediaDevices?.getUserMedia &&
    typeof MediaRecorder !== 'undefined';

  // Audio uploads are tier-gated on the backend (media_controller's
  // check_audio_allowed). Only show the mic when the user's tier actually
  // permits audio, otherwise recording just 403s on upload. The recording
  // length is capped to the tier's audio_duration for the same reason.
  let audioAllowed = $derived($currentUser?.limits?.audio_allowed ?? false);
  let maxRecordSeconds = $derived($currentUser?.limits?.audio_duration ?? 120);
  let showMic = $derived(canRecord && audioAllowed);

  const RECORD_MIME =
    typeof MediaRecorder === 'undefined'
      ? ''
      : ['audio/webm', 'audio/ogg', 'audio/mp4'].find((t) => MediaRecorder.isTypeSupported(t)) || '';

  let recording = $state(false);
  let recordSeconds = $state(0);
  let mediaRecorder: MediaRecorder | null = null;
  let recordChunks: Blob[] = [];
  let recordStream: MediaStream | null = null;
  let recordTimer: ReturnType<typeof setInterval> | null = null;
  let discardOnStop = false;

  let recordLabel = $derived(
    `${Math.floor(recordSeconds / 60)}:${String(recordSeconds % 60).padStart(2, '0')}`,
  );

  async function startRecording() {
    if (disabled || recording) return;
    if (uploaded.length + uploadingCount >= maxAttachments) {
      addToast(`Maximum ${maxAttachments} attachments per message`, 'error');
      return;
    }
    try {
      recordStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch {
      addToast('Microphone access is needed for voice messages', 'error');
      return;
    }
    recordChunks = [];
    discardOnStop = false;
    mediaRecorder = new MediaRecorder(recordStream, RECORD_MIME ? { mimeType: RECORD_MIME } : undefined);
    mediaRecorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) recordChunks.push(e.data);
    };
    mediaRecorder.onstop = finalizeRecording;
    mediaRecorder.start();
    recording = true;
    recordSeconds = 0;
    recordTimer = setInterval(() => {
      recordSeconds += 1;
      // Stop at the tier's max audio duration so the upload isn't rejected.
      if (recordSeconds >= maxRecordSeconds) stopRecording();
    }, 1000);
  }

  function stopRecording() {
    if (!recording) return;
    discardOnStop = false;
    mediaRecorder?.stop();
  }

  function cancelRecording() {
    if (!recording) return;
    discardOnStop = true;
    mediaRecorder?.stop();
  }

  function teardownRecorder() {
    if (recordTimer) {
      clearInterval(recordTimer);
      recordTimer = null;
    }
    recordStream?.getTracks().forEach((t) => t.stop());
    recordStream = null;
    recording = false;
  }

  async function finalizeRecording() {
    const chunks = recordChunks;
    const cancelled = discardOnStop;
    const rawType = mediaRecorder?.mimeType || RECORD_MIME || 'audio/webm';
    const type = rawType.split(';')[0]; // drop any ;codecs=… so the type is a plain MIME
    teardownRecorder();
    recordChunks = [];
    if (cancelled || chunks.length === 0) return;
    const ext = type.includes('ogg') ? 'ogg' : type.includes('mp4') ? 'm4a' : 'webm';
    const file = new File([new Blob(chunks, { type })], `voice-message.${ext}`, { type });
    await uploadFiles([file]);
  }

  onDestroy(() => {
    if (recording) {
      discardOnStop = true;
      mediaRecorder?.stop();
    }
    teardownRecorder();
  });

  function handleSubmit() {
    const trimmed = content.trim();
    if (!canSend) return;
    onsend?.(trimmed, uploaded.map((m) => m.id), replyingTo?.id ?? null);
    content = '';
    uploaded = [];
    if (textareaEl) {
      textareaEl.style.height = 'auto';
    }
  }

  // Compact preview text — falls back to "Attachment" so a reply to a
  // photo-with-no-caption still shows something meaningful.
  let replyPreviewText = $derived.by(() => {
    if (!replyingTo) return '';
    const text = (replyingTo.content || '').trim();
    if (text) return text;
    if ((replyingTo.media_attachments || []).length > 0) return 'Attachment';
    return '';
  });
  let replyAuthor = $derived(
    replyingTo?.sender?.display_name || replyingTo?.sender?.handle || '',
  );

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
    pingTyping();
  }

  // Throttle "I'm typing" pings — at most one every 2.5s while the user
  // is actively editing, so we hint the other side without hammering the
  // endpoint on every keystroke.
  let lastTypingPing = 0;
  function pingTyping() {
    if (!content.trim()) return;
    const now = Date.now();
    if (now - lastTypingPing < 2500) return;
    lastTypingPing = now;
    ontyping?.();
  }

  // Allow sending when there's text OR at least one finished attachment.
  // While an upload is still in flight, keep the user from racing it —
  // the server would reject media_ids that aren't ready yet.
  let canSend = $derived(
    !disabled &&
      uploadingCount === 0 &&
      (content.trim().length > 0 || uploaded.length > 0),
  );

  function previewKind(m: MediaAttachment): 'image' | 'video' | 'audio' | 'other' {
    if (m.type === 'image' || m.type === 'gifv') return 'image';
    if (m.type === 'video') return 'video';
    if (m.type === 'audio') return 'audio';
    return 'other';
  }
</script>

<div class="message-input-bar">
  {#if replyingTo}
    <div class="reply-banner" role="status">
      <span class="reply-banner-bar" aria-hidden="true"></span>
      <div class="reply-banner-body">
        <span class="reply-banner-label">Replying to {replyAuthor || 'message'}</span>
        {#if replyPreviewText}
          <span class="reply-banner-preview" dir="auto">{replyPreviewText}</span>
        {/if}
      </div>
      <button
        type="button"
        class="reply-banner-cancel"
        onclick={() => oncancelreply?.()}
        aria-label="Cancel reply"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </button>
    </div>
  {/if}
  {#if uploaded.length > 0 || uploadingCount > 0}
    <div class="attachment-row">
      {#each uploaded as m (m.id)}
        {@const kind = previewKind(m)}
        <div class="attachment-tile" title={m.description ?? m.id}>
          {#if kind === 'image' && (m.preview_url || m.url)}
            <img src={m.preview_url ?? m.url} alt="" />
          {:else if kind === 'video'}
            <div class="attachment-icon">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polygon points="23 7 16 12 23 17 23 7" />
                <rect x="1" y="5" width="15" height="14" rx="2" ry="2" />
              </svg>
            </div>
          {:else if kind === 'audio'}
            <div class="attachment-icon">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M9 18V5l12-2v13" />
                <circle cx="6" cy="18" r="3" />
                <circle cx="18" cy="16" r="3" />
              </svg>
            </div>
          {:else}
            <div class="attachment-icon">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <polyline points="14 2 14 8 20 8" />
              </svg>
            </div>
          {/if}
          <button
            type="button"
            class="attachment-remove"
            onclick={() => removeAttachment(m.id)}
            aria-label="Remove attachment"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>
      {/each}
      {#each Array(uploadingCount) as _, i (i)}
        <div class="attachment-tile attachment-tile-loading" aria-label="Uploading">
          <div class="attachment-spinner"></div>
        </div>
      {/each}
    </div>
  {/if}

  {#if recording}
    <div class="recording-bar" role="status">
      <span class="recording-dot" aria-hidden="true"></span>
      <span class="recording-time">Recording… {recordLabel}</span>
      <div class="recording-actions">
        <button type="button" class="recording-cancel" onclick={cancelRecording} aria-label="Cancel recording">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
            <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>
        <button type="button" class="recording-send" onclick={stopRecording} aria-label="Stop and attach recording">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="22" y1="2" x2="11" y2="13" /><polygon points="22 2 15 22 11 13 2 9 22 2" />
          </svg>
        </button>
      </div>
    </div>
  {/if}

  <div class="message-input-row">
    <input
      bind:this={fileInputEl}
      type="file"
      class="file-input"
      accept={ACCEPT_ATTR}
      multiple
      onchange={handleFileSelected}
      aria-hidden="true"
      tabindex="-1"
    />

    <button
      type="button"
      class="attach-btn"
      onclick={triggerFileInput}
      aria-label="Attach media"
      disabled={disabled || uploaded.length + uploadingCount >= maxAttachments}
    >
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48" />
      </svg>
    </button>

    {#if showMic}
      <button
        type="button"
        class="mic-btn"
        onclick={startRecording}
        aria-label="Record voice message"
        disabled={disabled || recording || uploaded.length + uploadingCount >= maxAttachments}
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <rect x="9" y="2" width="6" height="12" rx="3" />
          <path d="M5 10v1a7 7 0 0 0 14 0v-1" />
          <line x1="12" y1="19" x2="12" y2="22" />
        </svg>
      </button>
    {/if}

    <textarea
      bind:this={textareaEl}
      bind:value={content}
      class="message-textarea"
      placeholder="Write a message..."
      rows="1"
      dir="auto"
      onkeydown={handleKeydown}
      oninput={autoResize}
      {disabled}
    ></textarea>

    <div class="emoji-picker-wrapper">
      <button
        type="button"
        class="emoji-btn"
        class:active={showEmoji}
        bind:this={emojiBtnEl}
        onclick={() => (showEmoji = !showEmoji)}
        aria-label="Insert emoji"
        aria-expanded={showEmoji}
        {disabled}
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10" />
          <path d="M8 14s1.5 2 4 2 4-2 4-2" />
          <line x1="9" y1="9" x2="9.01" y2="9" />
          <line x1="15" y1="9" x2="15.01" y2="9" />
        </svg>
      </button>
      {#if showEmoji}
        <EmojiPicker onselect={insertEmoji} anchor={emojiBtnEl} onclose={() => (showEmoji = false)} />
      {/if}
    </div>

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
</div>

<style>
  .message-input-bar {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding: var(--space-3) var(--space-4);
    border-block-start: 1px solid var(--color-border);
    background: var(--color-bg);
  }

  .message-input-row {
    display: flex;
    align-items: flex-end;
    gap: var(--space-2);
  }

  .file-input {
    /* Visually hidden but still focusable / clickable via .click() —
       display: none would block the synthetic click on some browsers. */
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
  }

  .attach-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
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

  .emoji-picker-wrapper {
    position: relative;
    display: flex;
    flex-shrink: 0;
  }

  .emoji-btn,
  .mic-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border: none;
    background: none;
    border-radius: var(--radius-full);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background var(--transition-fast), color var(--transition-fast);
    flex-shrink: 0;
  }

  .emoji-btn:hover:not(:disabled),
  .emoji-btn.active,
  .mic-btn:hover:not(:disabled) {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .emoji-btn:disabled,
  .mic-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .recording-bar {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    margin-block-end: var(--space-2);
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
    border-radius: var(--radius-lg);
  }

  .recording-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--color-danger);
    flex-shrink: 0;
    animation: recording-pulse 1.2s ease-in-out infinite;
  }

  @keyframes recording-pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  .recording-time {
    flex: 1;
    font-size: var(--text-sm);
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .recording-actions {
    display: flex;
    align-items: center;
    gap: var(--space-1);
  }

  .recording-cancel,
  .recording-send {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border: none;
    border-radius: var(--radius-full);
    cursor: pointer;
    color: currentColor;
    background: transparent;
    transition: background var(--transition-fast);
  }

  .recording-cancel:hover {
    background: rgba(0, 0, 0, 0.1);
  }

  .recording-send {
    background: var(--color-primary);
    color: var(--color-on-primary);
  }

  .recording-send:hover {
    background: var(--color-primary-hover, var(--color-primary));
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
    /* Pair with dir="auto" — lets browser pick LTR/RTL from the first
       strong character, and text-align: start flips the alignment
       along with it so Arabic/Hebrew input right-aligns automatically. */
    text-align: start;
    unicode-bidi: plaintext;
  }

  /* iOS Safari auto-zooms the page when a focused input's font is < 16px and
     never zooms back. Lift to 16px on touch pointers only, so the DM composer
     doesn't jolt on focus. Pointer devices keep the compact --text-sm. This is
     a functional fix for a browser zoom bug, not a design change. */
  @media (pointer: coarse) {
    .message-textarea {
      font-size: 16px;
    }
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
    width: 40px;
    height: 40px;
    border: none;
    background: var(--color-surface-container);
    border-radius: var(--radius-full);
    color: var(--color-text-tertiary);
    cursor: pointer;
    transition:
      background var(--transition-fast),
      color var(--transition-fast),
      transform var(--transition-fast);
    flex-shrink: 0;
  }

  /* Once there's something to send, the button becomes a solid accent
     circle — a clear, discoverable primary action. */
  .send-btn.active {
    background: var(--gradient-primary);
    color: var(--color-text-on-primary);
    box-shadow: 0 1px 4px rgba(var(--color-primary-rgb), 0.18);
  }

  .send-btn.active:hover:not(:disabled) {
    transform: scale(1.05);
  }

  .send-btn:disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }

  .reply-banner {
    display: flex;
    align-items: stretch;
    gap: var(--space-2);
    padding: 6px 8px;
    background: var(--color-surface);
    border-radius: var(--radius-md);
  }

  .reply-banner-bar {
    flex-shrink: 0;
    width: 3px;
    border-radius: 999px;
    background: var(--color-primary);
  }

  .reply-banner-body {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    flex: 1;
  }

  .reply-banner-label {
    font-size: 12px;
    font-weight: 600;
    color: var(--color-primary);
  }

  .reply-banner-preview {
    font-size: 12px;
    color: var(--color-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .reply-banner-cancel {
    align-self: flex-start;
    width: 24px;
    height: 24px;
    border: none;
    background: transparent;
    color: var(--color-text-secondary);
    border-radius: var(--radius-full);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .reply-banner-cancel:hover {
    background: var(--color-bg);
    color: var(--color-text);
  }

  .attachment-row {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
  }

  .attachment-tile {
    position: relative;
    width: 64px;
    height: 64px;
    border-radius: var(--radius-md);
    overflow: hidden;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    flex-shrink: 0;
  }

  .attachment-tile img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .attachment-icon {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--color-text-secondary);
  }

  .attachment-remove {
    position: absolute;
    top: 2px;
    right: 2px;
    width: 20px;
    height: 20px;
    border-radius: var(--radius-full);
    background: var(--scrim-medium);
    color: #fff;
    border: none;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .attachment-remove:hover {
    background: var(--scrim-strong);
  }

  .attachment-tile-loading {
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .attachment-spinner {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    border: 2px solid var(--color-border);
    border-top-color: var(--color-primary);
    animation: dm-spin 0.7s linear infinite;
  }

  @keyframes dm-spin {
    to { transform: rotate(360deg); }
  }
</style>

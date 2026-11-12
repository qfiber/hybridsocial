<script lang="ts">
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import { api } from '$lib/api/client.js';
  import { uploadMedia, updateMedia } from '$lib/api/media.js';
  import { search } from '$lib/api/search.js';
  import type { Post, MediaAttachment, Identity, PostDraft, TrendingTag } from '$lib/api/types.js';
  import { createDraft, updateDraft, getDraft, deleteDraft } from '$lib/api/drafts.js';
  import { currentUser, authStore } from '$lib/stores/auth.js';
  import { preferencesStore } from '$lib/stores/preferences.js';
  import { addToast } from '$lib/stores/toast.js';
  import EmojiPicker from './EmojiPicker.svelte';
  import ImageLightbox from '$lib/components/ui/ImageLightbox.svelte';
  import { markSeen } from '$lib/utils/seen-posts.js';
  import { locale, t } from '$lib/stores/i18n.js';
  import { ApiError } from '$lib/api/client.js';
  import { t as translate } from '$lib/utils/i18n.js';

  type ComposerVisibility = 'public' | 'followers' | 'direct';

  // Mirrors what the backend's media validator accepts
  // (backend/lib/hybridsocial/media/validator.ex). Anything outside this set
  // is rejected at the picker / drag / paste boundary so we never start an
  // upload that the server will refuse, which is what produced the
  // "Processing…" tile that hung forever.
  const ACCEPTED_MIME_TYPES = new Set([
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/avif',
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
  // Extension fallback for browsers / drag sources that hand us a blank
  // or wrong MIME type (common with copy-from-Finder on macOS).
  const ACCEPTED_EXTENSIONS = new Set([
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif',
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

  // The user's saved default — set in /settings/privacy and persisted
  // both to localStorage (preferencesStore) and to the server
  // (users.default_visibility, returned from /auth/me). Falls back to
  // 'public' if the preference isn't a value the composer understands
  // (e.g. an admin-set 'unlisted' which we don't expose in the UI).
  function defaultVisibility(): ComposerVisibility {
    const pref = get(preferencesStore).default_visibility;
    if (pref === 'public' || pref === 'followers' || pref === 'direct') return pref;
    return 'public';
  }

  // `showFab` hides the floating "new post" button on routes where
  // composing from scratch doesn't make sense (DMs, settings, admin)
  // while still letting the composer be opened programmatically via
  // the `open-composer` window event — that's how the DM→direct-post
  // fallback works: posting is still possible, just not surfaced.
  let { showFab = true }: { showFab?: boolean } = $props();

  let isOpen = $state(false);
  let content = $state('');
  let visibility = $state<ComposerVisibility>(defaultVisibility());
  let spoilerText = $state('');
  let showCW = $state(false);
  let loading = $state(false);
  let error = $state('');
  // Set while a publish is in flight: puts what was written back if it's refused.
  let restoreWritten: ((message: string) => void) | null = null;

  type PostRateLimitBody = {
    error: string;
    window: 'minute' | 'hour' | 'day';
    limit: number;
    retry_after: number;
  };
  let replyTo = $state<Post | null>(null);
  // Set true when the parent post is edited while the composer is
  // open. Surfaces a "Post edited" indicator next to the
  // 'Replying to @user' line so the user knows the conversation
  // they're typing into has changed.
  let parentEdited = $state(false);
  // When the reply was opened from the lightbox of a multi-image
  // post, this holds the index (1-based) and id of the targeted
  // media so the composer can both display "Replying to image N"
  // and submit `target_media_id` to the API.
  let targetMediaId = $state<string | null>(null);
  let targetMediaIndex = $state<number | null>(null);
  let quotePost = $state<Post | null>(null);
  // Posting context — when set via the open-composer event from a
  // group or page detail screen, the resulting post is scoped to
  // that container rather than the global timeline.
  let groupId = $state<string | null>(null);
  let pageId = $state<string | null>(null);
  let contextLabel = $state<string | null>(null);

  // Tier-aware limits
  let charLimit = $derived($currentUser?.limits?.char_limit ?? 5000);
  let maxMedia = $derived($currentUser?.limits?.media_per_post ?? 4);
  let maxPollOptions = $derived($currentUser?.limits?.poll_options ?? 4);
  let canSchedule = $derived($currentUser?.limits?.scheduled_posts ?? false);
  // Markdown is tier-gated. Only expose the toggle when the user's
  // tier actually allows something beyond plaintext — otherwise the
  // button would be a no-op. Default to on; server caps at tier level.
  let markdownLevel = $derived(($currentUser?.limits as any)?.markdown ?? 'basic');
  let canMarkdown = $derived(markdownLevel && markdownLevel !== 'none');
  let markdownEnabled = $state(true);
  let textareaEl: HTMLTextAreaElement | undefined = $state();
  let fileInputEl: HTMLInputElement | undefined = $state();

  // Media state
  let uploadedMedia = $state<MediaAttachment[]>([]);
  let mediaUploading = $state(false);

  // Emoji picker state
  let showEmojiPicker = $state(false);
  let emojiBtnEl = $state<HTMLButtonElement | undefined>();
  let showGifPicker = $state(false);

  // Schedule state
  let showSchedule = $state(false);
  let scheduledAt = $state('');


  // Poll state
  let showPoll = $state(false);
  let pollOptions = $state<string[]>(['', '']);
  let pollDuration = $state('86400'); // 1 day in seconds
  let pollMultiple = $state(false);

  let pollDurations = $derived([
    { value: '3600', label: $t('composer.duration_1_hour') },
    { value: '21600', label: $t('composer.duration_6_hours') },
    { value: '86400', label: $t('composer.duration_1_day') },
    { value: '259200', label: $t('composer.duration_3_days') },
    { value: '604800', label: $t('composer.duration_7_days') },
  ]);

  let charCount = $derived(content.length);
  let charsRemaining = $derived(charLimit - charCount);
  let isOverLimit = $derived(charsRemaining < 0);

  // Direct posts are audience-scoped by @mentions in the content;
  // a direct post with zero mentions would be addressed to no one
  // (silent "me only"). Block send until at least one mention lands
  // so the user doesn't ship a post into the void.
  let mentionCount = $derived(
    (content.match(/@[a-zA-Z0-9_]+(@[a-zA-Z0-9.\-]+)?/g) ?? []).length,
  );
  let directNeedsAudience = $derived(visibility === 'direct' && mentionCount === 0);

  let canSubmit = $derived(
    // Require text OR at least one media attachment — a media-only
    // post (photo, video clip) is a perfectly valid post.
    (content.trim().length > 0 || uploadedMedia.length > 0)
    && !isOverLimit
    && !loading
    && !mediaUploading
    && !directNeedsAudience
    && (!showPoll || (pollOptions.filter((o) => o.trim()).length >= 2))
  );

  // Listen for open-composer events (from reply buttons, etc)
  onMount(() => {
    function handleOpenComposer(e: Event) {
      const detail = (e as CustomEvent).detail;
      if (detail?.replyTo) {
        replyTo = detail.replyTo;
        // Default the reply to the parent's visibility — a reply
        // to a direct post staying public would leak the thread to
        // followers who weren't in the original audience. User can
        // still widen visibility explicitly before sending.
        const parentVis = detail.replyTo.visibility;
        if (parentVis === 'public' || parentVis === 'followers' || parentVis === 'direct') {
          visibility = parentVis;
        }
      }
      if (detail?.targetMediaId) {
        targetMediaId = detail.targetMediaId;
        targetMediaIndex = detail.targetMediaIndex ?? null;
      } else {
        targetMediaId = null;
        targetMediaIndex = null;
      }
      if (detail?.quotePost) {
        quotePost = detail.quotePost;
      }
      if (detail?.prefill) {
        content = detail.prefill;
      }
      // Explicit visibility wins over the replyTo default — the DM
      // fallback flow passes { visibility: 'direct' } even without
      // a replyTo, and callers prefilling a direct reply want that
      // to stick.
      if (
        detail?.visibility &&
        ['public', 'followers', 'direct'].includes(detail.visibility)
      ) {
        visibility = detail.visibility;
      }
      if (detail?.groupId) {
        groupId = detail.groupId;
        pageId = null;
        contextLabel = detail.contextLabel ?? translate('composer.posting_to_group');
      }
      if (detail?.pageId) {
        pageId = detail.pageId;
        groupId = null;
        contextLabel = detail.contextLabel ?? translate('composer.posting_to_page');
      }
      if (detail?.draftId) {
        loadDraftById(detail.draftId);
        return;
      }
      openComposer();
    }

    window.addEventListener('open-composer', handleOpenComposer);

    // Check for saved draft
    hasDraft = !!localStorage.getItem('hs_post_draft');

    return () => window.removeEventListener('open-composer', handleOpenComposer);
  });

  // Live "Post edited" indicator: while a reply context is set,
  // open an SSE stream to /api/v1/streaming/post/:id and flip
  // `parentEdited` if the author edits the parent. The effect
  // tears the EventSource down whenever replyTo changes (or the
  // composer unmounts), so we never leak streams across reply
  // sessions.
  $effect(() => {
    const parent = replyTo;
    if (!parent?.id) return;

    parentEdited = false;
    const es = new EventSource(`/api/v1/streaming/post/${parent.id}`, {
      withCredentials: true,
    });

    const onEdit = () => {
      parentEdited = true;
    };
    es.addEventListener('edit', onEdit);

    return () => {
      es.removeEventListener('edit', onEdit);
      es.close();
    };
  });

  function resumeDraft() {
    loadDraft();
    hasDraft = false;
    openComposer();
  }

  function discardDraft() {
    clearDraft();
    hasDraft = false;
  }

  // --- Drafts ---
  const DRAFT_KEY = 'hs_post_draft';

  function saveDraft() {
    if (!content.trim() && !spoilerText.trim()) return;
    const draft = {
      content,
      spoilerText,
      showCW,
      visibility,
      savedAt: Date.now(),
    };
    localStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
  }

  function loadDraft(): boolean {
    try {
      const raw = localStorage.getItem(DRAFT_KEY);
      if (!raw) return false;
      const draft = JSON.parse(raw);
      // Discard drafts older than 7 days
      if (Date.now() - draft.savedAt > 7 * 86400 * 1000) {
        localStorage.removeItem(DRAFT_KEY);
        return false;
      }
      content = draft.content || '';
      spoilerText = draft.spoilerText || '';
      showCW = draft.showCW || false;
      visibility = draft.visibility || 'public';
      return true;
    } catch {
      return false;
    }
  }

  function clearDraft() {
    localStorage.removeItem(DRAFT_KEY);
  }

  let hasDraft = $state(false);

  // Server draft state — the id of the draft we're currently editing (if any),
  // plus a "saving" flag for the Save as draft button.
  let activeServerDraftId: string | null = $state(null);
  let savingServerDraft = $state(false);

  // Applies a server-side PostDraft to the composer state. Called when the
  // user clicks Resume from the drafts list page (which opens the composer
  // via the open-composer event with a `draft` payload) or via loadDraftById.
  function applyServerDraft(draft: PostDraft) {
    activeServerDraftId = draft.id;
    content = draft.content || '';
    spoilerText = draft.spoiler_text || '';
    showCW = !!draft.spoiler_text;
    visibility = (draft.visibility as 'public' | 'followers' | 'direct') || 'public';
    // Restore the group / page anchor + the matching context label so
    // the user sees the "Posting to <group>" banner on resume,
    // not a confusing reset to "Posting to your profile".
    groupId = draft.group_id ?? null;
    pageId = draft.page_id ?? null;
    if (groupId && draft.group) {
      contextLabel = translate('composer.posting_to_named', { name: draft.group.name });
    } else if (pageId && draft.page) {
      contextLabel = translate('composer.posting_to_named', { name: draft.page.name });
    } else {
      contextLabel = null;
    }
    if (draft.scheduled_at) {
      showSchedule = true;
      scheduledAt = draft.scheduled_at;
    }
    if (draft.poll_options && draft.poll_options.length > 0) {
      showPoll = true;
      pollOptions = draft.poll_options;
      pollMultiple = !!draft.poll_multiple;
    }
  }

  async function loadDraftById(id: string) {
    try {
      const draft = await getDraft(id);
      applyServerDraft(draft);
      openComposer();
    } catch {
      error = translate('composer.draft_load_failed');
    }
  }

  async function saveAsServerDraft() {
    if (savingServerDraft) return;
    if (!content.trim() && uploadedMedia.length === 0) {
      error = translate('composer.draft_needs_content');
      return;
    }
    savingServerDraft = true;
    error = '';
    try {
      const payload = {
        content,
        spoiler_text: showCW ? spoilerText : null,
        sensitive: showCW,
        visibility,
        media_ids: uploadedMedia.map((m) => m.id),
        parent_id: replyTo?.id ?? null,
        quote_id: quotePost?.id ?? null,
        // Persist the group / page anchor so resuming the draft from
        // the drafts list publishes back to the same place. Without
        // these, a "saved draft" silently degraded to a profile post
        // on resume.
        group_id: groupId,
        page_id: pageId,
        scheduled_at: showSchedule && scheduledAt ? new Date(scheduledAt).toISOString() : null,
        poll_options: showPoll ? pollOptions.filter((o) => o.trim()) : null,
        poll_multiple: showPoll && pollMultiple,
      };

      if (activeServerDraftId) {
        await updateDraft(activeServerDraftId, payload);
      } else {
        const saved = await createDraft(payload);
        activeServerDraftId = saved.id;
      }

      // Clear the localStorage auto-save — we don't need two sources.
      clearDraft();
      hasDraft = false;
      resetComposer();
    } catch {
      error = translate('composer.draft_save_failed');
    } finally {
      savingServerDraft = false;
    }
  }

  function openComposer() {
    isOpen = true;
    hasOpened = false;
    // Tag the body so the global keyboard-shortcut handler swallows
    // single-key keys (n, j, k, …) while the composer is open. Esc
    // still passes through (the composer wires its own close handler).
    document.body.dataset.composerOpen = 'true';
    // Mark opened after pop-in animation completes
    setTimeout(() => { hasOpened = true; }, 250);
    // Focus textarea on next tick
    setTimeout(() => textareaEl?.focus(), 50);
  }

  let discardConfirmOpen = $state(false);

  function closeComposer() {
    // Ask before nuking in-progress work. Localstorage draft survives
    // either way for text (saveDraft below), but media attachments +
    // a poll/schedule/visibility setup aren't recoverable, so a
    // confirm prompt before exit is the safer default.
    const hasWork =
      content.trim().length > 0 ||
      uploadedMedia.length > 0 ||
      showPoll ||
      showSchedule ||
      (showCW && spoilerText.trim().length > 0);

    if (hasWork) {
      discardConfirmOpen = true;
      return;
    }
    resetComposer();
  }

  function confirmDiscard() {
    discardConfirmOpen = false;
    if (content.trim()) saveDraft();
    resetComposer();
  }

  function cancelDiscard() {
    discardConfirmOpen = false;
  }

  let isClosing = $state(false);
  let isNudging = $state(false);
  let hasOpened = $state(false);

  function nudgeComposer() {
    if (isNudging) return;
    isNudging = true;
    setTimeout(() => { isNudging = false; }, 400);
  }

  let closeTimer: ReturnType<typeof setTimeout> | undefined;

  function resetComposer() {
    isClosing = true;
    closeTimer = setTimeout(() => {
      isClosing = false;
      isOpen = false;
      delete document.body.dataset.composerOpen;
    }, 200);
    content = '';
    spoilerText = '';
    showCW = false;
    // Snap back to the user's saved default for the *next* compose
    // session — so a one-off "this thread is followers-only" doesn't
    // become sticky after the post is sent.
    visibility = defaultVisibility();
    replyTo = null;
    parentEdited = false;
    targetMediaId = null;
    targetMediaIndex = null;
    quotePost = null;
    groupId = null;
    pageId = null;
    contextLabel = null;
    error = '';
    uploadedMedia = [];
    showPoll = false;
    pollOptions = ['', ''];
    pollDuration = '86400';
    pollMultiple = false;
    showSchedule = false;
    scheduledAt = '';
    activeServerDraftId = null;
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
    const files = Array.from(input.files ?? []);
    input.value = '';
    if (files.length === 0) return;
    await uploadFiles(files);
  }

  // In-flight progress entries shown in the composer. Each entry
  // tracks one File the user is uploading so a slow connection sees
  // a real bar per attachment, not just an "uploading…" toggle.
  type UploadProgress = {
    id: string;
    name: string;
    size: number;
    fraction: number;
  };
  let uploadingProgress = $state<UploadProgress[]>([]);

  // Drag/drop state. We track a depth counter rather than just a
  // boolean because dragenter/dragleave fire as the cursor crosses
  // child elements, and a naive flag would flicker as the user
  // moved over the textarea / toolbar nested inside the panel.
  let dragDepth = $state(0);
  let isDragOver = $derived(dragDepth > 0);

  function hasFiles(e: DragEvent): boolean {
    const types = e.dataTransfer?.types;
    if (!types) return false;
    // `Array.from` so we can call includes regardless of the runtime
    // returning a DOMStringList (some browsers) vs an array (most).
    return Array.from(types).includes('Files');
  }

  function handleDragEnter(e: DragEvent) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    dragDepth += 1;
  }

  function handleDragOver(e: DragEvent) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
  }

  function handleDragLeave(e: DragEvent) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    dragDepth = Math.max(0, dragDepth - 1);
  }

  async function handleDrop(e: DragEvent) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    dragDepth = 0;
    const files = Array.from(e.dataTransfer?.files ?? []);
    if (files.length === 0) return;
    await uploadFiles(files);
  }

  // Shared upload path so the file-picker, drag-drop, and paste-image
  // entry points all enforce the same accepted-types gate, the same
  // per-post cap, the same error mapping, and append into the same
  // uploadedMedia list.
  async function uploadFiles(files: File[]) {
    if (files.length === 0) return;

    // Reject unsupported types up front. The backend's magic-byte check
    // would refuse them anyway, but the user previously saw the tile sit
    // on "Processing…" until the server replied — gate at the boundary.
    const accepted = files.filter(isAcceptedFile);
    const unsupported = files.length - accepted.length;
    if (accepted.length === 0) {
      error =
        unsupported === 1
          ? translate('composer.file_unsupported_one')
          : translate('composer.files_unsupported_many', { count: unsupported });
      return;
    }
    files = accepted;

    const remaining = maxMedia - uploadedMedia.length;
    if (remaining <= 0) {
      error = translate('composer.max_media', { max: maxMedia });
      return;
    }

    // Trim anything past the per-post cap; tell the user what we
    // dropped instead of silently truncating.
    const toUpload = files.slice(0, remaining);
    const dropped = files.length - toUpload.length;

    mediaUploading = true;
    error = '';
    let failures = 0;

    // Track the first specific error so we can show something more
    // useful than "N uploads failed" when the backend rejects audio
    // on tier / size / duration grounds.
    let firstErrorMsg = '';

    // Seed progress entries up front so the bars render immediately
    // even before the first byte is on the wire.
    const progressEntries: UploadProgress[] = toUpload.map((f) => ({
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
      name: f.name,
      size: f.size,
      fraction: 0,
    }));
    uploadingProgress = [...uploadingProgress, ...progressEntries];

    function setFraction(id: string, fraction: number) {
      uploadingProgress = uploadingProgress.map((p) =>
        p.id === id ? { ...p, fraction } : p,
      );
    }

    try {
      // Upload in parallel — each media goes through media.upload() +
      // optional antivirus which can each be slow; waiting on them
      // sequentially would frustrate anyone attaching 4 photos.
      const results = await Promise.allSettled(
        toUpload.map((f, i) =>
          uploadMedia(f, undefined, (fraction) =>
            setFraction(progressEntries[i].id, fraction),
          ),
        ),
      );

      const succeeded: MediaAttachment[] = [];
      for (const r of results) {
        if (r.status === 'fulfilled') {
          succeeded.push(r.value);
        } else {
          failures += 1;
          if (!firstErrorMsg) firstErrorMsg = describeUploadError(r.reason);
        }
      }

      if (succeeded.length > 0) {
        uploadedMedia = [...uploadedMedia, ...succeeded];
      }
    } finally {
      mediaUploading = false;
      const ids = new Set(progressEntries.map((p) => p.id));
      uploadingProgress = uploadingProgress.filter((p) => !ids.has(p.id));
    }

    if (failures > 0 || dropped > 0 || unsupported > 0) {
      const parts: string[] = [];
      if (firstErrorMsg) {
        parts.push(firstErrorMsg);
      } else if (failures > 0) {
        parts.push(translate('composer.uploads_failed', { count: failures }));
      }
      if (unsupported > 0) {
        parts.push(translate('composer.unsupported_files', { count: unsupported }));
      }
      if (dropped > 0) parts.push(translate('composer.dropped_skipped', { count: dropped, max: maxMedia }));
      error = parts.join(' · ');
    }
  }

  function formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  // Translate the backend's upload error codes to human text. The
  // media controller uses distinct keys for audio so the composer
  // can point at the specific tier limit that was hit.
  function describeUploadError(reason: unknown): string {
    const body = (reason as { body?: { error?: string; max_mb?: number; max_seconds?: number } })?.body;
    const err = body?.error;
    switch (err) {
      case 'media.audio_not_allowed':
        return translate('composer.err_audio_not_allowed');
      case 'media.audio_too_large':
        return translate('composer.err_audio_too_large', { mb: body?.max_mb ?? '?' });
      case 'media.audio_too_long':
        return translate('composer.err_audio_too_long', { seconds: body?.max_seconds ?? '?' });
      case 'media.audio_invalid':
        return translate('composer.err_audio_invalid');
      case 'media.audio_scanner_unavailable':
        return translate('composer.err_audio_scanner_unavailable');
      case 'media.file_too_large':
        return translate('composer.err_file_too_large', { mb: body?.max_mb ?? '?' });
      case 'media.invalid_content_type':
        return translate('composer.err_invalid_type');
      case 'media.infected':
        return translate('composer.err_infected');
      default:
        return '';
    }
  }

  // Alt-text editor for an attached media. Backend accepts
  // PUT /api/v1/media/:id with alt_text/description.
  let altEditorOpen = $state(false);
  let altEditorMedia: MediaAttachment | null = $state(null);
  let altEditorValue = $state('');
  let altEditorSaving = $state(false);

  function openAltEditor(media: MediaAttachment) {
    altEditorMedia = media;
    altEditorValue = media.description || '';
    altEditorOpen = true;
  }

  async function saveAltText() {
    if (!altEditorMedia) return;
    altEditorSaving = true;
    try {
      const trimmed = altEditorValue.trim();
      const updated = await updateMedia(altEditorMedia.id, { description: trimmed });
      // Reflect the new alt text in the local preview without
      // re-fetching the list — optimistic posts use this field too.
      uploadedMedia = uploadedMedia.map((m) =>
        m.id === altEditorMedia!.id ? { ...m, description: updated.description ?? trimmed } : m
      );
      altEditorOpen = false;
    } catch {
      error = translate('composer.alt_save_failed');
    } finally {
      altEditorSaving = false;
    }
  }

  function removeMedia(id: string) {
    uploadedMedia = uploadedMedia.filter((m) => m.id !== id);
  }

  // --- Media preview lightbox ---
  // The composer used to be the only place a user could see their
  // attachment as a tiny 100-px thumbnail with no way to verify the
  // crop / orientation / blurhash matched what they meant to upload.
  // Tapping any image / video tile opens a fullscreen preview built
  // off the same ImageLightbox the timeline uses, with previous /
  // next nav across all attachments.
  let lightboxOpen = $state(false);
  let lightboxIndex = $state(0);

  function isImageMedia(m: MediaAttachment): boolean {
    const ct = (m as unknown as { content_type?: string }).content_type ?? '';
    return m.type === 'image' || m.type === 'gifv' || ct.startsWith('image/');
  }

  function isVideoMedia(m: MediaAttachment): boolean {
    const ct = (m as unknown as { content_type?: string }).content_type ?? '';
    return m.type === 'video' || ct.startsWith('video/');
  }

  // Slides for the lightbox: images use the original / preview url
  // straight; videos render inside a `<video>` thumbnail with a poster
  // — the lightbox itself is image-only so we let it show the still
  // and clicking through plays the file in the browser's native
  // viewer (open in new tab) for now. The slides array is built off
  // `uploadedMedia` directly so the index stays aligned with the
  // tile the user clicked.
  let lightboxSlides = $derived(
    uploadedMedia
      .filter((m) => isImageMedia(m))
      .map((m) => ({
        id: m.id,
        url: m.url || m.preview_url || '',
        alt: m.description ?? null,
      })),
  );

  function openMediaPreview(media: MediaAttachment, e: MouseEvent | KeyboardEvent) {
    // Stop click bubbling so the parent media-preview-item buttons
    // (Remove, ALT) behave as before — only the cover area opens
    // the lightbox.
    e.stopPropagation();

    if (isImageMedia(media)) {
      const idx = lightboxSlides.findIndex((s) => s.id === media.id);
      lightboxIndex = idx >= 0 ? idx : 0;
      lightboxOpen = true;
      return;
    }

    if (isVideoMedia(media)) {
      // Videos: hand off to a transient `<video controls>` overlay
      // rather than threading video support through the image
      // lightbox (which has no playback chrome).
      videoPreviewSrc = media.url || media.preview_url || '';
      videoPreviewOpen = !!videoPreviewSrc;
    }
  }

  let videoPreviewOpen = $state(false);
  let videoPreviewSrc = $state('');

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

  // --- Hashtag autocomplete ---
  // Mirrors the mention flow above. `#` and `@` are distinct triggers, so
  // at most one of the two dropdowns is ever active for the token at the
  // cursor. Backed by the OpenSearch prefix search on hashtag names
  // (usage-ranked, Unicode → works for AR + EN).
  let hashtagSuggestions = $state<TrendingTag[]>([]);
  let hashtagActive = $state(false);
  let hashtagIndex = $state(0);
  let hashtagQuery = $state('');
  let hashtagAtPos = $state(0);
  let hashtagDebounce: ReturnType<typeof setTimeout> | null = null;

  // Caret-anchored position for the mention/hashtag popup so it sits right
  // under the word being typed rather than at the bottom of a tall textarea.
  let acTop = $state(0);
  let acLeft = $state(0);

  function updateAcPos() {
    if (!textareaEl) return;
    const c = caretCoords(textareaEl, textareaEl.selectionStart);
    const cs = getComputedStyle(textareaEl);
    const lh = parseFloat(cs.lineHeight) || 20;
    acTop = c.top - textareaEl.scrollTop + lh + 4;
    // Clamp so the popup never spills past the textarea's right edge.
    const maxLeft = Math.max(0, textareaEl.clientWidth - 240);
    acLeft = Math.min(Math.max(0, c.left - textareaEl.scrollLeft), maxLeft);
  }

  // Mirror-div caret measurement: render the text up to the caret in a
  // hidden div that copies the textarea's box + font metrics, then read a
  // marker span's offset to get the caret's pixel position in the textarea.
  function caretCoords(el: HTMLTextAreaElement, position: number): { top: number; left: number } {
    const div = document.createElement('div');
    const cs = getComputedStyle(el);
    const copy = [
      'boxSizing', 'width', 'borderTopWidth', 'borderLeftWidth',
      'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
      'fontStyle', 'fontVariant', 'fontWeight', 'fontStretch', 'fontSize',
      'lineHeight', 'fontFamily', 'textAlign', 'textIndent', 'letterSpacing',
      'wordSpacing', 'tabSize',
    ];
    for (const p of copy) (div.style as unknown as Record<string, string>)[p] = (cs as unknown as Record<string, string>)[p];
    div.style.position = 'absolute';
    div.style.visibility = 'hidden';
    div.style.whiteSpace = 'pre-wrap';
    div.style.wordWrap = 'break-word';
    div.textContent = el.value.substring(0, position);
    const span = document.createElement('span');
    span.textContent = el.value.substring(position) || '.';
    div.appendChild(span);
    document.body.appendChild(div);
    const top = span.offsetTop + parseFloat(cs.borderTopWidth || '0');
    const left = span.offsetLeft + parseFloat(cs.borderLeftWidth || '0');
    document.body.removeChild(div);
    return { top, left };
  }

  function handleTextareaInput() {
    autoGrow();
    detectMention();
    detectHashtag();
  }

  // Pull every image File off the clipboard. clipboardData.files and
  // clipboardData.items both reference the pasted bitmap, but
  // .items[].getAsFile() returns a *fresh* File object each time, so
  // a naive identity Set won't dedupe a paste that surfaces in both.
  // Prefer `.files` when populated (modern Chrome/Firefox) and only
  // fall back to `.items` when it's empty (older Safari paths).
  function collectPastedImages(cd: DataTransfer | null): File[] {
    if (!cd) return [];

    const fromFiles = Array.from(cd.files ?? []).filter(
      (f) => f.type.startsWith('image/') && isAcceptedFile(f),
    );
    if (fromFiles.length > 0) return fromFiles;

    const fromItems: File[] = [];
    for (const item of Array.from(cd.items ?? [])) {
      if (item.kind === 'file' && item.type.startsWith('image/')) {
        const f = item.getAsFile();
        if (f && isAcceptedFile(f)) fromItems.push(f);
      }
    }
    return fromItems;
  }

  function handlePaste(e: ClipboardEvent) {
    // Image paste — screenshot tools, "Copy image" from a browser,
    // Snipping Tool, etc. all hand the bitmap over via clipboardData.
    // Treat it like a normal upload so the user can drop a screenshot
    // into the composer without saving-then-attaching first.
    const imageFiles = collectPastedImages(e.clipboardData);
    if (imageFiles.length > 0) {
      e.preventDefault();
      uploadFiles(imageFiles);
      return;
    }

    // Prefer text/plain when available. For a user copying markdown
    // source, this is what preserves their pipes, emoji, newlines, etc.
    // Only fall back to parsing text/html when the plain version is
    // missing (rare — usually happens for drag-drop from Office-y apps).
    const plain = e.clipboardData?.getData('text/plain');
    if (plain && plain.trim().length > 0) {
      // Let the browser insert text/plain natively; it handles the
      // cursor placement and auto-scroll correctly without us having
      // to re-implement any of it.
      return;
    }

    const html = e.clipboardData?.getData('text/html');
    if (!html) return;

    e.preventDefault();
    // Extract text from HTML, preserving as much structure as a plain
    // textarea can show:
    //   * <table> rows become newline-separated, cells joined with " | "
    //   * <img alt="…"> becomes its alt text (emoji as <img>)
    //   * <br>, </p>, </div>, </li> become line breaks
    //   * everything else gets tag-stripped
    let text = html
      // Table cells → " | " separators, rows → newlines.
      .replace(/<\/(th|td)>\s*<(th|td)[^>]*>/gi, ' | ')
      .replace(/<\/tr>\s*<tr[^>]*>/gi, '\n')
      .replace(/<t(?:head|body|r|h|d)[^>]*>/gi, '')
      .replace(/<\/t(?:head|body|r|h|d)>/gi, '')
      .replace(/<\/table>/gi, '\n')
      // Preserve image alt text (Gemini/ChatGPT render emoji as <img>).
      .replace(/<img[^>]*alt="([^"]*)"[^>]*>/gi, '$1')
      .replace(/<img\b[^>]*>/gi, '')
      // Block-level → newlines.
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(p|div|li|h[1-6])>/gi, '\n')
      // Strip remaining tags.
      .replace(/<[^>]+>/g, '')
      // Decode common entities last, so text like "&lt;div&gt;" doesn't
      // get re-swept by the tag stripper above.
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#(\d+);/g, (_, n: string) => String.fromCodePoint(Number(n)))
      .replace(/&#x([0-9a-f]+);/gi, (_, n: string) => String.fromCodePoint(parseInt(n, 16)))
      .replace(/\n{3,}/g, '\n\n')
      .trim();

    if (textareaEl) {
      const start = textareaEl.selectionStart;
      const end = textareaEl.selectionEnd;
      content = content.substring(0, start) + text + content.substring(end);
      setTimeout(() => {
        if (textareaEl) {
          const newPos = start + text.length;
          textareaEl.selectionStart = newPos;
          textareaEl.selectionEnd = newPos;
          autoGrow();
        }
      }, 0);
    }
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
      updateAcPos();

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
    // Use acct (user@domain for remote, handle for local)
    const before = content.substring(0, mentionAtPos);
    const after = content.substring(cursor);
    const mention = account.acct || account.handle;
    const mentionText = `${mention} `;
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

  function detectHashtag() {
    if (!textareaEl) return;
    const cursor = textareaEl.selectionStart;
    const text = content.substring(0, cursor);

    // Last `#tag` token at the cursor: must follow whitespace/start and
    // begin with a letter (matches the server-side tag rule, so we don't
    // suggest for `#123`). Unicode-aware so Arabic tags work.
    const match = text.match(/(?:^|[\s\n])#(\p{L}[\p{L}\p{M}\p{N}_]*)$/u);
    if (match) {
      const query = match[1];
      hashtagAtPos = cursor - query.length;
      hashtagQuery = query;
      updateAcPos();

      // Fire after 2 letters, per the request ("first 2-3 letters").
      if (query.length >= 2) {
        if (hashtagDebounce) clearTimeout(hashtagDebounce);
        hashtagDebounce = setTimeout(() => fetchHashtagSuggestions(query), 200);
      } else {
        hashtagSuggestions = [];
        hashtagActive = false;
      }
    } else {
      closeHashtags();
    }
  }

  async function fetchHashtagSuggestions(query: string) {
    try {
      const results = await search(query, { type: 'hashtags', limit: 6 });
      hashtagSuggestions = results.hashtags || [];
      hashtagActive = hashtagSuggestions.length > 0;
      hashtagIndex = 0;
    } catch {
      hashtagSuggestions = [];
      hashtagActive = false;
    }
  }

  function selectHashtag(tag: TrendingTag) {
    if (!textareaEl) return;
    const cursor = textareaEl.selectionStart;
    // `before` keeps the leading `#`; replace the partial query with the
    // chosen tag name and drop a trailing space to continue typing.
    const before = content.substring(0, hashtagAtPos);
    const after = content.substring(cursor);
    const insertText = `${tag.name} `;
    content = before + insertText + after;
    closeHashtags();
    setTimeout(() => {
      if (textareaEl) {
        const newPos = hashtagAtPos + insertText.length;
        textareaEl.selectionStart = newPos;
        textareaEl.selectionEnd = newPos;
        textareaEl.focus();
      }
    }, 0);
  }

  function handleHashtagKeydown(e: KeyboardEvent) {
    if (!hashtagActive) return;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      hashtagIndex = (hashtagIndex + 1) % hashtagSuggestions.length;
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      hashtagIndex = (hashtagIndex - 1 + hashtagSuggestions.length) % hashtagSuggestions.length;
    } else if (e.key === 'Enter' || e.key === 'Tab') {
      if (hashtagSuggestions.length > 0) {
        e.preventDefault();
        selectHashtag(hashtagSuggestions[hashtagIndex]);
      }
    } else if (e.key === 'Escape') {
      e.preventDefault();
      closeHashtags();
    }
  }

  function closeHashtags() {
    hashtagActive = false;
    hashtagSuggestions = [];
    hashtagQuery = '';
    if (hashtagDebounce) clearTimeout(hashtagDebounce);
  }

  // The textarea's keydown drives whichever autocomplete is open (never
  // both at once — `@` and `#` are different triggers).
  function handleComposerKeydown(e: KeyboardEvent) {
    if (mentionActive) handleMentionKeydown(e);
    else if (hashtagActive) handleHashtagKeydown(e);
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
      if (canMarkdown && !markdownEnabled) {
        // Explicit opt-down to plaintext for this post, even though
        // the tier allows GFM. Backend honors this as "markdown: none".
        body.markdown = false;
      }
      if (showCW) {
        // The NSFW toggle marks the post sensitive on its own — the
        // warning text is optional. Gating `sensitive` on a non-empty
        // spoilerText meant "NSFW, no description" silently saved as a
        // normal post (issue #52). The description is only sent when the
        // user actually wrote one.
        body.sensitive = true;
        if (spoilerText.trim()) {
          body.spoiler_text = spoilerText;
        }
      }
      if (replyTo) {
        body.parent_id = replyTo.id;
        if (targetMediaId) {
          body.target_media_id = targetMediaId;
        }
      }
      if (quotePost) {
        body.quote_id = quotePost.id;
      }
      if (groupId) {
        body.group_id = groupId;
      }
      if (pageId) {
        body.page_id = pageId;
      }
      if (uploadedMedia.length > 0) {
        body.media_ids = uploadedMedia.map((m) => m.id);

        const isVideo = (m: MediaAttachment) =>
          m.type === 'video' || ((m as any).content_type || '').startsWith('video/');
        const isAudio = (m: MediaAttachment) =>
          m.type === 'audio' || ((m as any).content_type || '').startsWith('audio/');

        if (uploadedMedia.every(isAudio)) {
          // All-audio → dedicated "audio" post type. The backend
          // enforces tier gating on create; if the user's tier is
          // free, the POST returns 403 with audio_not_allowed.
          body.post_type = 'audio';
        } else if (uploadedMedia.every(isVideo)) {
          // All-video → Streams feed.
          body.post_type = 'video_stream';
        } else if (!content.trim()) {
          // Image-only post with no caption — mark as "media" so the
          // backend's content-required validator (which otherwise
          // demands text for post_type="text") doesn't reject it.
          body.post_type = 'media';
        }
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
      if (showSchedule && scheduledAt) {
        body.scheduled_at = new Date(scheduledAt).toISOString();
      }

      // Create optimistic post for immediate display
      const optimisticId = `pending-${Date.now()}`;
      const auth = get(authStore);
      const contentStr = String(body.content || '');

      // Build optimistic poll if present
      let optimisticPoll = null;
      if (showPoll) {
        const validOpts = pollOptions.filter((o) => o.trim());
        if (validOpts.length >= 2) {
          optimisticPoll = {
            id: optimisticId + '-poll',
            options: validOpts.map(title => ({ title, votes_count: 0 })),
            votes_count: 0,
            voters_count: 0,
            voted: false,
            own_votes: [],
            multiple: pollMultiple,
            expired: false,
            expires_at: body.expires_at || null,
          };
        }
      }

      const optimisticType =
        body.post_type === 'video_stream'
          ? 'video_stream'
          : uploadedMedia.length > 0
            ? 'media'
            : optimisticPoll
              ? 'poll'
              : 'text';

      const optimisticPost = {
        id: optimisticId,
        type: optimisticType,
        post_type: optimisticType,
        content: contentStr,
        content_html: contentStr ? `<p>${contentStr.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\n\n+/g, '</p><p>').replace(/\n/g, '<br>')}</p>` : null,
        visibility: body.visibility,
        sensitive: body.sensitive || false,
        spoiler_text: body.spoiler_text || null,
        language: null,
        reply_count: 0,
        boost_count: 0,
        reaction_count: 0,
        is_pinned: false,
        is_boosted: false,
        is_bookmarked: false,
        is_muted: false,
        current_user_reaction: null,
        created_at: new Date().toISOString(),
        edited_at: null,
        account: auth.user,
        parent_id: body.parent_id || null,
        root_id: null,
        in_reply_to_account_id: null,
        quote: null,
        card: null,
        mentions: [],
        tags: [],
        emojis: [],
        reactions: [],
        poll: optimisticPoll,
        media_attachments: uploadedMedia.map(m => ({
          id: m.id,
          type: m.type || 'image',
          url: m.url || m.preview_url || '',
          preview_url: m.preview_url || m.url || '',
          remote_url: null,
          description: m.description || null,
          blurhash: m.blurhash || null,
          meta: null,
        })),
        uri: '',
        url: '',
        pending: true,
      };

      // Capture parent ID before reset clears it
      const parentId = replyTo?.id;
      // A root post's counter covers its whole thread, so a reply deeper down
      // bumps the root as well as the direct parent.
      const rootId = replyTo?.root_id && replyTo.root_id !== parentId ? replyTo.root_id : null;

      // Show optimistic post immediately
      window.dispatchEvent(new CustomEvent('new-post', { detail: optimisticPost }));

      // The composer clears right away, but a refused post must not lose what
      // was written: keep it all, and the drafts, until the server has said yes.
      const draftToDelete = activeServerDraftId;
      const written = {
        content, spoilerText, showCW, visibility, replyTo, parentEdited,
        targetMediaId, targetMediaIndex, quotePost, groupId, pageId, contextLabel,
        uploadedMedia, showPoll, pollOptions, pollDuration, pollMultiple,
        showSchedule, scheduledAt,
      };
      restoreWritten = (message: string) => {
        window.dispatchEvent(new CustomEvent('post-deleted', { detail: { id: optimisticId } }));
        if (parentId) {
          window.dispatchEvent(new CustomEvent('reply-count-update', { detail: { postId: parentId, delta: -1 } }));
        }
        if (rootId) {
          window.dispatchEvent(new CustomEvent('reply-count-update', { detail: { postId: rootId, delta: -1 } }));
        }
        clearTimeout(closeTimer);
        isClosing = false;
        isOpen = true;
        document.body.dataset.composerOpen = 'true';
        ({
          content, spoilerText, showCW, visibility, replyTo, parentEdited,
          targetMediaId, targetMediaIndex, quotePost, groupId, pageId, contextLabel,
          uploadedMedia, showPoll, pollOptions, pollDuration, pollMultiple,
          showSchedule, scheduledAt,
        } = written);
        activeServerDraftId = draftToDelete;
        error = message;
      };

      resetComposer();

      // Increment parent's reply count immediately
      if (parentId) {
        markSeen(parentId);
        window.dispatchEvent(new CustomEvent('reply-count-update', { detail: { postId: parentId, delta: 1 } }));
      }
      if (rootId) {
        window.dispatchEvent(new CustomEvent('reply-count-update', { detail: { postId: rootId, delta: 1 } }));
      }

      // Send to server, then replace optimistic with real
      const newPost = await api.post('/api/v1/statuses', body);
      window.dispatchEvent(new CustomEvent('post-replace', { detail: { oldId: optimisticId, post: newPost } }));

      // Published, so the drafts have served their purpose. Fire-and-forget.
      clearDraft();
      if (draftToDelete) deleteDraft(draftToDelete).catch(() => {});

      // Confirm the publish. A scheduled post isn't live yet, so only offer a
      // "View post" link for a real, immediately-visible one.
      const newPostId = (newPost as { id?: string } | null)?.id;
      if (body.scheduled_at) {
        addToast(translate('composer.post_scheduled'), 'success');
      } else if (newPostId) {
        addToast(translate('composer.post_published'), 'success', 5000, undefined, {
          label: translate('composer.view_post'),
          href: `/post/${newPostId}`,
        });
      } else {
        addToast(translate('composer.post_published'), 'success');
      }
    } catch (err) {
      const message = publishErrorMessage(err);
      if (restoreWritten) restoreWritten(message);
      else error = message;
    } finally {
      restoreWritten = null;
      loading = false;
    }
  }

  // Tells someone over a posting limit which limit it was and when they can post
  // again, rather than a generic failure they would just retry.
  function publishErrorMessage(err: unknown): string {
    const body = err instanceof ApiError ? (err.body as unknown as PostRateLimitBody) : null;
    if (body?.error !== 'limits.post_rate_limit') return translate('composer.publish_failed');
    return translate('composer.rate_limited', {
      limit: body.limit,
      window: translate(`composer.rate_window_${body.window}`),
      when: relativeRetry(body.retry_after),
    });
  }

  function relativeRetry(seconds: number): string {
    const format = new Intl.RelativeTimeFormat(get(locale), { numeric: 'always' });
    if (seconds < 60) return format.format(seconds, 'second');
    if (seconds < 3600) return format.format(Math.ceil(seconds / 60), 'minute');
    return format.format(Math.ceil(seconds / 3600), 'hour');
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

  let visibilityOptions = $derived([
    { value: 'public' as const, label: $t('post.visibility.public'), icon: 'public' },
    { value: 'followers' as const, label: $t('post.visibility.followers'), icon: 'lock' },
    { value: 'direct' as const, label: $t('post.visibility.direct'), icon: 'mail' },
  ]);

  let visibilityMenuOpen = $state(false);
  let visibilityCurrent = $derived(
    visibilityOptions.find((o) => o.value === visibility) ?? visibilityOptions[0],
  );

  function setVisibility(v: ComposerVisibility) {
    visibility = v;
    visibilityMenuOpen = false;
  }
</script>

<!-- Floating action button -->
{#if !isOpen && showFab}
  <button
    type="button"
    class="fab"
    onclick={openComposer}
    aria-label={$t('composer.compose_new')}
  >
    <span class="material-symbols-outlined fab-icon">edit</span>
  </button>
{/if}

<!-- Draft banner -->
{#if hasDraft && !isOpen}
  <div class="draft-banner">
    <span class="material-symbols-outlined draft-icon">edit_note</span>
    <span class="draft-text">{$t('composer.unsaved_draft')}</span>
    <button type="button" class="draft-resume" onclick={resumeDraft}>{$t('composer.resume')}</button>
    <button type="button" class="draft-discard" onclick={discardDraft}>
      <span class="material-symbols-outlined" style="font-size: 16px">close</span>
    </button>
  </div>
{/if}

<!-- Composer panel -->
{#if isOpen}
  <div class="composer-backdrop" class:composer-fadeout={isClosing} role="presentation" onclick={nudgeComposer}></div>
  <div
    class="composer-panel"
    class:composer-opened={hasOpened}
    class:composer-panel-fadeout={isClosing}
    class:composer-nudge={isNudging}
    class:composer-drag-over={isDragOver}
    role="dialog"
    aria-label={$t('composer.compose_post')}
    aria-modal="true"
    onkeydown={handleKeydown}
    onclick={handleEmojiClickOutside}
    ondragenter={handleDragEnter}
    ondragover={handleDragOver}
    ondragleave={handleDragLeave}
    ondrop={handleDrop}
  >
    {#if isDragOver}
      <div class="composer-drop-overlay" aria-hidden="true">
        <span class="material-symbols-outlined composer-drop-icon">upload_file</span>
        <span class="composer-drop-text">{$t('composer.drop_files')}</span>
      </div>
    {/if}
    <button
      type="button"
      class="composer-close"
      onclick={closeComposer}
      aria-label={$t('composer.close_composer')}
      title={$t('composer.close_draft_saved')}
    >
      <span class="material-symbols-outlined">close</span>
    </button>

    {#if replyTo}
      <div class="composer-reply-context">
        {$t('post.replying_to')} <strong>@{replyTo.account.acct || replyTo.account.handle}</strong>
        {#if parentEdited}
          <span class="composer-parent-edited" title={$t('composer.parent_edited_title')}>
            <span class="material-symbols-outlined" aria-hidden="true">edit</span>
            {$t('composer.edited')}
          </span>
        {/if}
        {#if targetMediaId}
          {@const targetMedia = replyTo.media_attachments?.find((m) => m.id === targetMediaId)}
          {#if targetMedia}
            <span class="composer-target-media">
              {#if targetMedia.preview_url || targetMedia.url}
                <img
                  class="composer-target-thumb"
                  src={targetMedia.preview_url || targetMedia.url}
                  alt=""
                />
              {/if}
              {$t('composer.on_image', { n: targetMediaIndex ?? '?' })}
            </span>
          {/if}
        {/if}
      </div>
    {/if}

    {#if (groupId || pageId) && contextLabel}
      <div class="composer-scope-context">
        <span class="material-symbols-outlined" aria-hidden="true">{groupId ? 'groups' : 'description'}</span>
        <span>{contextLabel}</span>
      </div>
    {/if}

    {#if quotePost}
      <div class="composer-quote-context">
        <div class="quote-preview">
          <span class="material-symbols-outlined" style="font-size: 16px; color: var(--color-primary)">format_quote</span>
          <div class="quote-preview-content">
            <strong>{quotePost.account.display_name || quotePost.account.handle}</strong>
            <p>{(quotePost.content || '').slice(0, 100)}{(quotePost.content || '').length > 100 ? '...' : ''}</p>
          </div>
          <button type="button" class="quote-remove" onclick={() => quotePost = null} aria-label={$t('composer.remove_quote')}>
            <span class="material-symbols-outlined" style="font-size: 16px">close</span>
          </button>
        </div>
      </div>
    {/if}

    {#if error}
      <div class="composer-error" role="alert">{error}</div>
    {/if}

    <div class="composer-body">
      <!-- Avatar -->
      <div class="composer-avatar">
        <img src={$currentUser?.avatar_url || '/images/default-avatar.svg'} alt="" class="composer-avatar-img" />
      </div>

      <!-- Text area -->
      <div class="composer-input-area">
        {#if showCW}
          <input
            type="text"
            class="composer-cw-input"
            placeholder={$t('composer.cw_placeholder')}
            bind:value={spoilerText}
            aria-label={$t('composer.cw_aria')}
            dir="auto"
          />
        {/if}

        <div class="textarea-wrapper">
          <textarea
            bind:this={textareaEl}
            bind:value={content}
            oninput={handleTextareaInput}
            onkeydown={handleComposerKeydown}
            onpaste={handlePaste}
            class="composer-textarea"
            placeholder={replyTo ? $t('composer.reply_placeholder', { handle: replyTo.account?.handle ?? replyTo.account?.acct ?? '' }) : quotePost ? $t('composer.quote_placeholder') : $t('composer.placeholder')}
            aria-label={$t('composer.content_aria')}
            rows={3}
            dir="auto"
          ></textarea>

          {#if mentionActive && mentionSuggestions.length > 0}
            <div class="mention-dropdown" role="listbox" aria-label={$t('composer.mention_suggestions')} style="top: {acTop}px; left: {acLeft}px;">
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
                    <span class="mention-handle">@{account.acct || account.handle}</span>
                  </div>
                </button>
              {/each}
            </div>
          {/if}

          {#if hashtagActive && hashtagSuggestions.length > 0}
            <div class="mention-dropdown" role="listbox" aria-label={$t('composer.hashtag_suggestions')} style="top: {acTop}px; left: {acLeft}px;">
              {#each hashtagSuggestions as tag, i (tag.name)}
                <button
                  type="button"
                  class="mention-item"
                  class:mention-item-active={i === hashtagIndex}
                  role="option"
                  aria-selected={i === hashtagIndex}
                  onclick={() => selectHashtag(tag)}
                  onmouseenter={() => hashtagIndex = i}
                >
                  <div class="mention-avatar-placeholder">#</div>
                  <div class="mention-info">
                    <span class="mention-name">#{tag.name}</span>
                  </div>
                </button>
              {/each}
            </div>
          {/if}
        </div>
      </div>
    </div>

    <!-- Media previews -->
    {#if uploadedMedia.length > 0 || uploadingProgress.length > 0}
      <div class="media-previews">
        {#each uploadedMedia as media (media.id)}
          {@const ct = (media as any).content_type || ''}
          {@const kind =
            media.type === 'image' || media.type === 'gifv' || ct.startsWith('image/')
              ? 'image'
              : media.type === 'video' || ct.startsWith('video/')
              ? 'video'
              : media.type === 'audio' || ct.startsWith('audio/')
              ? 'audio'
              : 'file'}
          {@const src = media.preview_url || media.url}
          <div class="media-preview-item">
            {#if kind === 'image' && src}
              <button
                type="button"
                class="media-preview-trigger"
                aria-label={$t('composer.preview_image')}
                onclick={(e) => openMediaPreview(media, e)}
              >
                <img src={src} alt={media.description || ''} class="media-preview-img" />
              </button>
            {:else if kind === 'video'}
              <button
                type="button"
                class="media-preview-trigger"
                aria-label={$t('composer.preview_video')}
                onclick={(e) => openMediaPreview(media, e)}
              >
                <video src={src} class="media-preview-img" muted preload="metadata"></video>
                <span class="material-symbols-outlined media-preview-video-overlay">play_arrow</span>
              </button>
            {:else if kind === 'audio'}
              <span class="material-symbols-outlined media-preview-icon">graphic_eq</span>
            {:else}
              <span class="material-symbols-outlined media-preview-icon">attach_file</span>
            {/if}
            <button
              type="button"
              class="media-preview-remove"
              onclick={() => removeMedia(media.id)}
              aria-label={$t('post.remove_attachment')}
            >
              <span class="material-symbols-outlined remove-icon">close</span>
            </button>
            <button
              type="button"
              class="media-preview-alt"
              class:media-preview-alt-set={!!media.description}
              onclick={() => openAltEditor(media)}
              aria-label={media.description ? $t('composer.edit_alt') : $t('composer.add_alt')}
              title={media.description || $t('composer.add_alt')}
            >
              ALT
            </button>
          </div>
        {/each}
        {#each uploadingProgress as up (up.id)}
          {@const pct = Math.round(up.fraction * 100)}
          <div class="media-preview-item media-preview-uploading" title={up.name}>
            <div class="upload-progress" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow={pct} aria-label={$t('composer.uploading_named', { name: up.name })}>
              <div class="upload-progress-meta">
                <span class="upload-progress-name">{up.name}</span>
                <span class="upload-progress-pct">{pct === 100 ? $t('composer.processing') : pct + '%'}</span>
              </div>
              <div class="upload-progress-track">
                <div
                  class="upload-progress-fill"
                  class:upload-progress-fill-indeterminate={pct >= 100}
                  style="width: {pct}%"
                ></div>
              </div>
              <span class="upload-progress-size">{formatBytes(up.size)}</span>
            </div>
          </div>
        {/each}
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
                placeholder={$t('composer.poll_option', { n: i + 1 })}
                value={option}
                oninput={(e) => updatePollOption(i, (e.target as HTMLInputElement).value)}
                aria-label={$t('composer.poll_option_aria', { n: i + 1 })}
              />
              {#if pollOptions.length > 2}
                <button
                  type="button"
                  class="poll-option-remove"
                  onclick={() => removePollOption(i)}
                  aria-label={$t('composer.remove_option', { n: i + 1 })}
                >
                  <span class="material-symbols-outlined remove-icon">close</span>
                </button>
              {/if}
            </div>
          {/each}
        </div>

        {#if pollOptions.length < maxPollOptions}
          <button type="button" class="poll-add-option" onclick={addPollOption}>
            + {$t('composer.add_option')}
          </button>
        {/if}

        <div class="poll-settings">
          <div class="poll-setting-row">
            <label class="poll-setting-label" for="poll-duration">{$t('composer.duration')}</label>
            <select id="poll-duration" class="poll-setting-select" bind:value={pollDuration}>
              {#each pollDurations as dur (dur.value)}
                <option value={dur.value}>{dur.label}</option>
              {/each}
            </select>
          </div>

          <label class="poll-setting-toggle">
            <input type="checkbox" bind:checked={pollMultiple} />
            <span>{$t('composer.multiple_choice')}</span>
          </label>
        </div>
      </div>
    {/if}

    {#if showSchedule}
      <div class="schedule-picker">
        <div class="schedule-header">
          <span class="material-symbols-outlined schedule-icon">schedule_send</span>
          <span class="schedule-label">{$t('composer.schedule_post')}</span>
        </div>
        <input
          type="datetime-local"
          class="schedule-input"
          bind:value={scheduledAt}
          min={new Date(Date.now() + 300000).toISOString().slice(0, 16)}
        />
        {#if scheduledAt}
          <p class="schedule-preview">
            {$t('composer.will_publish', { date: new Date(scheduledAt).toLocaleString() })}
          </p>
        {/if}
      </div>
    {/if}

    <!-- Hidden file input -->
    <input
      bind:this={fileInputEl}
      type="file"
      accept={ACCEPT_ATTR}
      multiple
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
          aria-label={$t('post.attach_media')}
          title={showPoll
            ? $t('composer.polls_media_exclusive')
            : $t('post.attach_hint', { max: maxMedia })}
          disabled={showPoll || mediaUploading}
        >
          <span class="material-symbols-outlined tool-icon">image</span>
        </button>

        <!-- Poll toggle -->
        <button
          type="button"
          class="tool-btn"
          class:tool-active={showPoll}
          onclick={togglePoll}
          aria-label={$t('composer.add_poll')}
          aria-pressed={showPoll}
          title={uploadedMedia.length > 0
            ? $t('composer.polls_media_exclusive')
            : showPoll
              ? $t('composer.remove_poll')
              : $t('composer.add_poll_title')}
          disabled={uploadedMedia.length > 0}
        >
          <span class="tool-icon-svg tool-icon-poll" aria-hidden="true"></span>
        </button>

        <!-- Schedule toggle -->
        {#if canSchedule}
          <button
            type="button"
            class="tool-btn"
            class:tool-active={showSchedule}
            onclick={() => showSchedule = !showSchedule}
            aria-label={$t('composer.schedule_post')}
            aria-pressed={showSchedule}
            title={showSchedule ? $t('composer.cancel_schedule') : $t('composer.schedule_later')}
          >
            <span class="tool-icon-svg tool-icon-schedule" aria-hidden="true"></span>
          </button>
        {/if}

        <!-- Emoji picker -->
        <div class="emoji-picker-wrapper">
          <button
            bind:this={emojiBtnEl}
            type="button"
            class="tool-btn"
            class:tool-active={showEmojiPicker}
            onclick={() => { showEmojiPicker = !showEmojiPicker; showGifPicker = false; }}
            aria-label={$t('composer.insert_emoji')}
            aria-expanded={showEmojiPicker}
            title={showEmojiPicker ? $t('composer.close_emoji') : $t('composer.insert_emoji')}
          >
            <span class="material-symbols-outlined tool-icon">mood</span>
          </button>
          {#if showEmojiPicker}
            <EmojiPicker onselect={insertEmoji} anchor={emojiBtnEl} onclose={() => (showEmojiPicker = false)} />
          {/if}
        </div>

        {#if canMarkdown}
          <!-- Markdown toggle. Tier-gated — free-tier users never
               see this because their posts are plaintext by server
               policy anyway. When off, the post is stored and
               rendered as plain text regardless of whether the
               source contains ** or # characters. -->
          <button
            type="button"
            class="tool-btn tool-btn-text"
            class:tool-active={markdownEnabled}
            onclick={() => (markdownEnabled = !markdownEnabled)}
            aria-pressed={markdownEnabled}
            title={markdownEnabled ? $t('composer.markdown_on') : $t('composer.markdown_off')}
          >
            MD
          </button>
        {/if}

        <!-- Visibility selector -->
        <div class="visibility-picker">
          <button
            type="button"
            class="tool-btn"
            class:tool-active={visibilityMenuOpen}
            onclick={() => (visibilityMenuOpen = !visibilityMenuOpen)}
            aria-label={$t('composer.visibility_aria', { label: visibilityCurrent.label })}
            aria-haspopup="menu"
            aria-expanded={visibilityMenuOpen}
            title={visibilityCurrent.label}
          >
            <span class="material-symbols-outlined tool-icon">{visibilityCurrent.icon}</span>
          </button>
          {#if visibilityMenuOpen}
            <!-- Click-away catcher: a fixed-position transparent layer
                 below the menu so clicking anywhere else dismisses it
                 without us having to wire a global listener. -->
            <button
              type="button"
              class="visibility-backdrop"
              aria-hidden="true"
              tabindex="-1"
              onclick={() => (visibilityMenuOpen = false)}
            ></button>
            <div class="visibility-menu" role="menu">
              {#each visibilityOptions as opt (opt.value)}
                <button
                  type="button"
                  class="visibility-menu-item"
                  class:visibility-menu-item-active={opt.value === visibility}
                  role="menuitemradio"
                  aria-checked={opt.value === visibility}
                  onclick={() => setVisibility(opt.value)}
                >
                  <span class="material-symbols-outlined visibility-menu-icon">{opt.icon}</span>
                  <span>{opt.label}</span>
                </button>
              {/each}
            </div>
          {/if}
        </div>

        <!-- NSFW toggle -->
        <button
          type="button"
          class="tool-btn tool-btn-text"
          class:tool-active={showCW}
          onclick={() => { showCW = !showCW; }}
          aria-label={$t('composer.toggle_nsfw')}
          aria-pressed={showCW}
          title={showCW
            ? $t('composer.remove_nsfw')
            : $t('composer.add_nsfw')}
        >
          NSFW
        </button>
      </div>

      <div class="composer-right">
        <span class="composer-char-count" class:over-limit={isOverLimit}>{charsRemaining}</span>
        <button
          type="button"
          class="composer-save-draft"
          disabled={savingServerDraft || loading || (!content.trim() && uploadedMedia.length === 0)}
          onclick={saveAsServerDraft}
          title={$t('composer.save_as_draft')}
        >
          {#if savingServerDraft}
            {$t('post.saving')}
          {:else}
            {activeServerDraftId ? $t('composer.update_draft') : $t('composer.save_draft')}
          {/if}
        </button>
        {#if directNeedsAudience}
          <span class="composer-hint" role="status">
            {$t('composer.direct_needs_mention')}
          </span>
        {/if}
        <button
          type="button"
          class="composer-submit"
          disabled={!canSubmit}
          onclick={handleSubmit}
        >
          {#if loading}
            <span class="spinner" aria-hidden="true"></span>
            {$t('post.posting')}
          {:else}
            {$t('composer.post_action')}
          {/if}
        </button>
      </div>
    </div>
  </div>
{/if}

{#if altEditorOpen && altEditorMedia}
  <div class="alt-overlay" role="dialog" aria-modal="true" aria-label={$t('composer.edit_alt')} onclick={(e) => { if (e.target === e.currentTarget) altEditorOpen = false; }}>
    <div class="alt-dialog">
      <h3 class="alt-title">{$t('composer.describe_image')}</h3>
      <p class="alt-hint">
        {$t('composer.alt_hint')}
      </p>
      <textarea
        class="alt-textarea"
        bind:value={altEditorValue}
        placeholder={$t('composer.alt_example')}
        rows="4"
        maxlength="1500"
        dir="auto"
        autofocus
      ></textarea>
      <div class="alt-char-count">{altEditorValue.length} / 1500</div>
      <div class="alt-actions">
        <button type="button" class="btn btn-ghost" onclick={() => (altEditorOpen = false)}>{$t('common.cancel')}</button>
        <button type="button" class="btn btn-primary" disabled={altEditorSaving} onclick={saveAltText}>
          {altEditorSaving ? $t('post.saving') : $t('common.save')}
        </button>
      </div>
    </div>
  </div>
{/if}

{#if discardConfirmOpen}
  <div class="alt-overlay" role="dialog" aria-modal="true" aria-label={$t('composer.discard_aria')}>
    <div class="alt-dialog discard-dialog">
      <h3 class="alt-title">{$t('composer.discard_title')}</h3>
      <p class="alt-hint">
        {uploadedMedia.length > 0 ? $t('composer.discard_body_media') : $t('composer.discard_body')}
      </p>
      <div class="alt-actions">
        <button type="button" class="btn btn-ghost" onclick={cancelDiscard}>{$t('composer.keep_writing')}</button>
        <button type="button" class="btn btn-danger" onclick={confirmDiscard}>{$t('composer.discard_close')}</button>
      </div>
    </div>
  </div>
{/if}

{#if lightboxOpen && lightboxSlides.length > 0}
  <ImageLightbox
    images={lightboxSlides}
    bind:index={lightboxIndex}
    onclose={() => (lightboxOpen = false)}
  />
{/if}

{#if videoPreviewOpen && videoPreviewSrc}
  <!-- Lightweight transient preview for video attachments. Closes
       on backdrop click or Escape; the inner video has native
       controls so the user can seek / pause without us
       reimplementing chrome. -->
  <div
    class="video-preview-overlay"
    role="dialog"
    aria-modal="true"
    aria-label={$t('composer.video_preview')}
    onclick={(e) => {
      if (e.target === e.currentTarget) {
        videoPreviewOpen = false;
        videoPreviewSrc = '';
      }
    }}
    onkeydown={(e) => {
      if (e.key === 'Escape') {
        videoPreviewOpen = false;
        videoPreviewSrc = '';
      }
    }}
    tabindex="-1"
  >
    <button
      type="button"
      class="video-preview-close"
      aria-label={$t('composer.close_preview')}
      onclick={() => {
        videoPreviewOpen = false;
        videoPreviewSrc = '';
      }}
    >
      <span class="material-symbols-outlined">close</span>
    </button>
    <!-- svelte-ignore a11y_media_has_caption -->
    <video src={videoPreviewSrc} class="video-preview-player" controls autoplay></video>
  </div>
{/if}

<style>
  .composer-hint {
    font-size: var(--text-xs);
    color: var(--color-warning, #d97706);
    margin-inline-end: var(--space-2);
    align-self: center;
  }

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
  /* Draft banner */
  .draft-banner {
    position: fixed;
    inset-block-end: 88px;
    inset-inline-end: 24px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 14px;
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-primary);
    border-radius: 14px;
    box-shadow: var(--shadow-md);
    z-index: var(--z-sticky, 40);
    animation: draft-in 0.3s ease;
  }

  @keyframes draft-in {
    from { opacity: 0; transform: translateY(8px); }
    to { opacity: 1; transform: translateY(0); }
  }

  .draft-icon { font-size: 20px; color: var(--color-primary); }
  .draft-text { font-size: 0.8125rem; font-weight: 500; color: var(--color-text); }

  .draft-resume {
    padding: 4px 14px;
    background: var(--color-primary);
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
  }

  .draft-resume:hover { opacity: 0.9; }

  .draft-discard {
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
    padding: 2px;
    border-radius: 50%;
    display: flex;
  }

  .draft-discard:hover { color: var(--color-text); background: var(--color-surface); }

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
    box-shadow: 0 2px 6px rgba(var(--color-primary-rgb), 0.2);
    transition: transform 150ms ease, box-shadow 150ms ease;
    z-index: var(--z-sticky);
  }

  .fab:hover {
    transform: scale(1.05);
    box-shadow: 0 3px 10px rgba(var(--color-primary-rgb), 0.28);
  }

  .fab:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 3px;
  }

  .fab-icon {
    font-size: 24px;
  }

  /* Drop zone — shown only while a file is being dragged over the
     composer. The overlay sits above the composer body so the user
     sees an unambiguous target, but `pointer-events: none` ensures
     dragleave/drop still fire on the panel itself. */
  .composer-drop-overlay {
    position: absolute;
    inset: 8px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    background: color-mix(in oklab, var(--color-primary) 12%, transparent);
    border: 2px dashed var(--color-primary);
    border-radius: var(--radius-lg);
    color: var(--color-primary);
    z-index: 5;
    pointer-events: none;
    backdrop-filter: blur(2px);
    -webkit-backdrop-filter: blur(2px);
    animation: composer-drop-in 120ms ease;
  }

  @keyframes composer-drop-in {
    from { opacity: 0; }
    to   { opacity: 1; }
  }

  .composer-drop-icon {
    font-size: 48px !important;
  }

  .composer-drop-text {
    font-size: 0.95rem;
    font-weight: 600;
  }

  .composer-panel.composer-drag-over {
    box-shadow: 0 0 0 2px var(--color-primary), var(--shadow-xl);
  }

  /* On mobile the BottomTabs bar already has a Compose button in
     the centre, so the floating FAB is redundant — and worse, it
     sits on top of the per-post action ⋯ menu and a post's right
     edge. Hide it at the same breakpoint that shows BottomTabs. */
  @media (max-width: 768px) {
    .fab {
      display: none;
    }
  }

  /* ---- Backdrop ---- */
  .composer-backdrop {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    z-index: var(--z-modal-backdrop);
    animation: fade-in 0.15s ease;
  }

  .composer-backdrop.composer-fadeout {
    animation: fade-out 0.2s ease forwards;
  }

  @keyframes fade-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes fade-out {
    from { opacity: 1; }
    to { opacity: 0; }
  }

  /* ---- Close button ---- */
  .composer-close {
    position: absolute;
    top: 12px;
    inset-inline-end: 12px;
    background: none;
    border: none;
    color: var(--color-on-surface-variant);
    cursor: pointer;
    padding: 4px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1;
    transition: background 0.15s ease, color 0.15s ease;
  }

  .composer-close:hover {
    background: var(--color-surface-container);
    color: var(--color-on-surface);
  }

  /* ---- Composer Card ---- */
  .composer-panel {
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: calc(100% - 32px);
    max-width: 560px;
    max-height: 80vh;
    max-height: 80dvh;
    background: var(--color-surface-container-lowest);
    border-radius: 14px;
    padding: 24px;
    box-shadow: var(--shadow-lg);
    z-index: var(--z-modal);
    /* Allow internal scroll once the content (textarea + many media
       tiles + footer) exceeds the panel's max-height — previously
       `overflow: visible` let the tile grid spill outside the rounded
       card on mobile when 8–10 attachments stacked vertically. */
    overflow-y: auto;
    overscroll-behavior: contain;
    animation: pop-in 0.2s ease both;
  }

  .composer-panel.composer-opened {
    animation: none;
  }

  .composer-panel.composer-nudge {
    animation: nudge 0.35s ease both;
  }

  .composer-panel.composer-panel-fadeout {
    animation: pop-out 0.2s ease forwards;
  }

  @keyframes pop-in {
    from { opacity: 0; transform: translate(-50%, -50%) scale(0.95); }
    to { opacity: 1; transform: translate(-50%, -50%) scale(1); }
  }

  @keyframes pop-out {
    from { opacity: 1; transform: translate(-50%, -50%) scale(1); }
    to { opacity: 0; transform: translate(-50%, -50%) scale(0.95); }
  }

  @keyframes nudge {
    0% { transform: translate(-50%, -50%) scale(1); }
    25% { transform: translate(-50%, -50%) scale(0.96); }
    55% { transform: translate(-50%, -50%) scale(1.02); }
    100% { transform: translate(-50%, -50%) scale(1); }
  }

  @media (min-width: 640px) {
    .composer-panel {
      border: 1px solid var(--color-border);
    }
  }

  /* ---- Reply context ---- */
  .composer-reply-context {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 6px;
    font-size: 0.875rem;
    color: var(--color-text-secondary);
    padding: 8px 12px;
    background: var(--color-surface);
    border-radius: 10px;
    margin-block-end: 16px;
  }

  .composer-target-media {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    color: var(--color-text);
  }

  .composer-parent-edited {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 0.75rem;
    color: var(--color-warning, #b45309);
    background: var(--color-warning-soft, rgba(245, 158, 11, 0.1));
    padding: 2px 8px;
    border-radius: 999px;
  }

  .composer-parent-edited .material-symbols-outlined {
    font-size: 14px;
  }

  .composer-target-thumb {
    width: 28px;
    height: 28px;
    object-fit: cover;
    border-radius: 4px;
  }

  /* Scope context — shown when posting into a group or page so the
     user knows the post won't land on their personal profile feed. */
  .composer-scope-context {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-primary);
    padding: 6px 12px;
    background: var(--color-primary-soft);
    border-radius: 999px;
    margin-block-end: 12px;
  }

  .composer-scope-context .material-symbols-outlined {
    font-size: 16px;
  }

  .composer-quote-context {
    margin-block-end: 12px;
  }

  .quote-preview {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    padding: 10px 14px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-inline-start: 3px solid var(--color-primary);
    border-radius: 8px;
  }

  .quote-preview-content {
    flex: 1;
    min-width: 0;
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
    line-height: 1.4;
  }

  .quote-preview-content strong {
    color: var(--color-text);
    display: block;
    margin-block-end: 2px;
  }

  .quote-preview-content p {
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .quote-remove {
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
    padding: 2px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .quote-remove:hover {
    background: var(--color-surface-container-low);
    color: var(--color-text);
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
    max-height: 40dvh;
    padding: 4px 0;
    border: none;
    font-size: 1.125rem;
    color: var(--color-text);
    background: transparent;
    resize: none;
    line-height: 1.6;
    /* Pair with dir="auto" so Arabic/Hebrew input flips alignment and
       glyph flow automatically based on the first strong-directional
       character. */
    text-align: start;
    unicode-bidi: plaintext;
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
    /* Indent under the textarea (48px avatar + 16px gap = 64px) so the
       grid lines up with the input on desktop. On narrow phones the
       indent leaves so little width that 80px tiles can only fit one
       per row and the layout looks ragged — the @media rule below
       drops the indent to recover the full content width. */
    margin-inline-start: 64px;
    min-width: 0;
  }

  @media (max-width: 600px) {
    .media-previews {
      margin-inline-start: 0;
    }
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

  /* Click target wrapping the image / video thumbnail. Resets the
     button defaults so the cover continues to fill the tile flush
     with the rounded corners; cursor + focus ring make it
     discoverable. */
  .media-preview-trigger {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    padding: 0;
    margin: 0;
    border: none;
    background: transparent;
    cursor: zoom-in;
    display: block;
    overflow: hidden;
  }

  .media-preview-trigger:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: -2px;
  }

  .media-preview-video-overlay {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #fff;
    font-size: 32px;
    pointer-events: none;
    background: rgba(0, 0, 0, 0.25);
  }

  .media-preview-icon {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--color-text-secondary);
    font-size: 28px;
  }

  .media-preview-loading {
    display: flex;
    align-items: center;
    justify-content: center;
  }

  /* Per-file upload progress card. Wider than image thumbnails because
     it has to hold the file name, status text, progress bar, and size
     stacked vertically — at the 80px square width inherited from
     .media-preview-item, "Processing…" overflowed and got clipped. */
  .media-preview-uploading {
    display: flex;
    align-items: stretch;
    justify-content: center;
    width: 160px;
    background: var(--color-surface);
    border: 1px dashed var(--color-border);
    padding: 10px;
  }

  .upload-progress {
    display: flex;
    flex-direction: column;
    gap: 6px;
    width: 100%;
    align-self: center;
    color: var(--color-text);
    font-size: 12px;
  }

  .upload-progress-meta {
    display: flex;
    justify-content: space-between;
    gap: 8px;
    align-items: center;
  }

  .upload-progress-name {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-weight: 600;
  }

  .upload-progress-pct {
    flex-shrink: 0;
    color: var(--color-text-secondary);
    font-variant-numeric: tabular-nums;
  }

  .upload-progress-track {
    width: 100%;
    height: 6px;
    border-radius: 9999px;
    background: var(--color-border);
    overflow: hidden;
  }

  .upload-progress-fill {
    height: 100%;
    background: var(--color-primary);
    transition: width 120ms linear;
  }

  /* Once the bytes have all left the browser we still wait on the
     server's antivirus + decoding. Animate the bar so the user
     doesn't think the upload stalled. */
  .upload-progress-fill-indeterminate {
    background: linear-gradient(
      90deg,
      var(--color-primary) 0%,
      var(--color-primary-hover, var(--color-primary)) 50%,
      var(--color-primary) 100%
    );
    background-size: 200% 100%;
    animation: upload-shimmer 1.2s linear infinite;
  }

  @keyframes upload-shimmer {
    from { background-position: 200% 0; }
    to   { background-position: -200% 0; }
  }

  .upload-progress-size {
    color: var(--color-text-tertiary, var(--color-text-secondary));
    font-size: 11px;
  }

  .media-preview-remove {
    position: absolute;
    inset-block-start: 4px;
    inset-inline-end: 4px;
    width: 22px;
    height: 22px;
    border-radius: 9999px;
    background: var(--scrim-medium);
    color: white;
    border: none;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    /* Stack above the cover-area click target so taps on the X
       trigger remove instead of the lightbox preview. */
    z-index: 2;
  }

  .media-preview-remove:hover {
    background: var(--scrim-strong);
  }

  .remove-icon {
    font-size: 14px;
  }

  /* ---- Poll Creator ---- */
  /* Schedule picker */
  .schedule-picker {
    padding: 12px 16px;
    background: var(--color-surface);
    border-radius: 10px;
    margin-block-end: 8px;
  }

  .schedule-header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-block-end: 10px;
  }

  .schedule-icon {
    font-size: 20px;
    color: var(--color-primary);
  }

  .schedule-label {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
  }

  .schedule-input {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 8px;
    font-size: 0.875rem;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
  }

  .schedule-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-soft, rgba(var(--color-primary-rgb), 0.1));
  }

  .schedule-preview {
    font-size: 0.75rem;
    color: var(--color-text-secondary);
    margin-block-start: 6px;
  }

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
    gap: 12px;
    flex-wrap: wrap;
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

  /* Custom SVG icons rendered via CSS mask so they pick up the
     button's `color` (matching the Material Symbols glyphs in the
     same toolbar). The SVG is monochrome — only its alpha matters. */
  .tool-icon-svg {
    display: inline-block;
    width: 22px;
    height: 22px;
    background-color: currentColor;
    -webkit-mask-position: center;
    mask-position: center;
    -webkit-mask-repeat: no-repeat;
    mask-repeat: no-repeat;
    -webkit-mask-size: contain;
    mask-size: contain;
  }

  .tool-icon-poll {
    -webkit-mask-image: url('/icons/poll.svg');
    mask-image: url('/icons/poll.svg');
  }

  .tool-icon-schedule {
    -webkit-mask-image: url('/icons/schedule.svg');
    mask-image: url('/icons/schedule.svg');
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

  .visibility-picker {
    position: relative;
    display: inline-flex;
  }

  .visibility-backdrop {
    position: fixed;
    inset: 0;
    background: transparent;
    border: none;
    padding: 0;
    margin: 0;
    cursor: default;
    z-index: 99;
  }

  .visibility-menu {
    position: absolute;
    inset-block-end: calc(100% + 6px);
    inset-inline-start: 0;
    z-index: 100;
    min-width: 180px;
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg, 12px);
    box-shadow: var(--shadow-md);
    padding: 4px;
    display: flex;
    flex-direction: column;
  }

  .visibility-menu-item {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 10px;
    background: transparent;
    border: none;
    border-radius: var(--radius-md, 8px);
    font-size: var(--text-sm);
    color: var(--color-text);
    text-align: start;
    cursor: pointer;
    width: 100%;
  }

  .visibility-menu-item:hover {
    background: var(--color-surface-hover, rgba(0, 0, 0, 0.04));
  }

  .visibility-menu-item-active {
    color: var(--color-primary);
    font-weight: 600;
  }

  .visibility-menu-icon {
    font-size: 20px;
    color: inherit;
  }

  .composer-right {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 8px;
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
    white-space: nowrap;
  }

  .composer-submit:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .composer-submit:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .composer-save-draft {
    display: inline-flex;
    align-items: center;
    padding: 8px 16px;
    background: transparent;
    color: var(--color-text);
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 150ms ease;
    white-space: nowrap;
  }

  .composer-save-draft:hover:not(:disabled) {
    background: var(--color-surface-hover);
  }

  .composer-save-draft:disabled {
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
    /* top/left are set inline from the caret position so the popup opens
       right under the word being typed (not at the bottom of the box). */
    position: absolute;
    min-width: 240px;
    max-width: min(320px, 100%);
    max-height: 240px;
    overflow-y: auto;
    background: var(--color-surface-container-lowest, #fff);
    border: 1px solid var(--color-border);
    border-radius: 12px;
    box-shadow: var(--shadow-md);
    z-index: 50;
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
    background: var(--color-primary, #6c3edd);
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

  /* ALT pill on each media preview */
  .media-preview-alt {
    position: absolute;
    inset-block-end: 4px;
    inset-inline-start: 4px;
    border: none;
    padding: 2px 8px;
    border-radius: 9999px;
    background: var(--scrim-medium);
    color: #fff;
    font-size: 0.65rem;
    font-weight: 700;
    letter-spacing: 0.05em;
    cursor: pointer;
    /* Layer above .media-preview-trigger so the ALT pill stays
       clickable instead of the cover swallowing the tap. */
    z-index: 2;
  }

  .media-preview-alt:hover {
    background: var(--scrim-strong);
  }

  .media-preview-alt-set {
    background: var(--color-primary);
  }

  .media-preview-alt-set:hover {
    background: var(--color-primary-hover);
  }

  /* Video preview overlay — sibling to ImageLightbox at the same
     z-index since they're mutually exclusive. */
  .video-preview-overlay {
    position: fixed;
    inset: 0;
    z-index: 10000;
    background: var(--scrim-strong);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-4);
    animation: alt-fade 0.2s ease;
  }

  .video-preview-player {
    max-width: min(960px, 100%);
    max-height: 90vh;
    max-height: 90dvh;
    border-radius: var(--radius-lg);
    background: #000;
  }

  .video-preview-close {
    position: absolute;
    top: var(--space-4);
    inset-inline-end: var(--space-4);
    width: 40px;
    height: 40px;
    border-radius: 50%;
    border: none;
    background: var(--scrim-medium);
    color: #fff;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .video-preview-close:hover {
    background: var(--scrim-strong);
  }

  /* Alt-text + discard-confirm overlays */
  .alt-overlay {
    position: fixed;
    inset: 0;
    z-index: 10000;
    background: var(--scrim-medium);
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-4);
    animation: alt-fade 0.2s ease;
  }

  @keyframes alt-fade {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .alt-dialog {
    background: var(--color-surface-raised);
    border-radius: var(--radius-xl);
    padding: var(--space-6);
    width: 100%;
    max-width: 480px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.25);
  }

  .alt-title {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .alt-hint {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-3);
    line-height: 1.5;
  }

  .alt-textarea {
    width: 100%;
    min-height: 96px;
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font: inherit;
    resize: vertical;
    box-sizing: border-box;
    background: var(--color-surface);
    color: var(--color-text);
  }

  .alt-textarea:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft);
  }

  .alt-char-count {
    text-align: end;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: 4px;
  }

  .alt-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-block-start: var(--space-4);
  }
</style>

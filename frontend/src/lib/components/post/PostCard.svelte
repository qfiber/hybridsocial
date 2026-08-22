<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import { goto, beforeNavigate } from '$app/navigation';
  import { relativeTime, relativeTimeFuture, fullDateTime } from '$lib/utils/time.js';
  import { editPost, getPost, translateStatus } from '$lib/api/statuses.js';
  import { uploadMedia } from '$lib/api/media.js';
  import { currentUser } from '$lib/stores/auth.js';
  import type { MediaAttachment } from '$lib/api/types.js';
  import { api } from '$lib/api/client.js';
  import { isStaffMember } from '$lib/stores/auth.js';
  import PostActions from './PostActions.svelte';
  import AdminPostActions from '$lib/components/admin/AdminPostActions.svelte';
  import QuoteCard from './QuoteCard.svelte';
  import VerifiedBadge from '$lib/components/ui/VerifiedBadge.svelte';
  import RoleBadge from '$lib/components/ui/RoleBadge.svelte';
  import ProfileHoverCard from '$lib/components/ui/ProfileHoverCard.svelte';
  import ImageLightbox from '$lib/components/ui/ImageLightbox.svelte';
  import { stripTrailingHashtags } from '$lib/utils/hashtag-footer.js';
  import { renderCustomEmojis } from '$lib/utils/custom-emoji.js';
  import DisplayName from '$lib/components/DisplayName.svelte';
  import { filterBadges, type Badge } from '$lib/utils/badges.js';
  import { t, availableLocales } from '$lib/stores/i18n.js';
  import { t as translate } from '$lib/utils/i18n.js';
  import { effectiveTranslationTarget, translationEnabled } from '$lib/stores/translation.js';
  import { addToast } from '$lib/stores/toast.js';

  // Seeded PRNG from post ID for deterministic wave patterns
  function seededRng(seed: string) {
    let h = 0;
    for (let i = 0; i < seed.length; i++) {
      h = Math.imul(31, h) + seed.charCodeAt(i) | 0;
    }
    return () => {
      h = Math.imul(h ^ (h >>> 16), 0x45d9f3b);
      h = Math.imul(h ^ (h >>> 13), 0x45d9f3b);
      h = (h ^ (h >>> 16)) >>> 0;
      return h / 0x100000000;
    };
  }

  function generateWavePaths(postId: string): string[] {
    const rng = seededRng(postId);
    const layers = 6;
    const paths: string[] = [];

    for (let l = 0; l < layers; l++) {
      const yBase = 10 + (l * 80) / layers + (rng() * 20 - 10);
      const points: [number, number][] = [];

      // Generate control points across the width
      for (let x = 0; x <= 100; x += 12 + rng() * 8) {
        const waveY = yBase + Math.sin((x / 100) * Math.PI * (1.5 + rng())) * (15 + rng() * 20);
        points.push([x, waveY + (rng() * 14 - 7)]);
      }
      points.push([100, points[points.length - 1][1]]);

      // Build smooth cubic bezier path
      let d = `M -5 ${points[0][1]}`;
      for (let i = 0; i < points.length - 1; i++) {
        const cx = (points[i][0] + points[i + 1][0]) / 2;
        d += ` C ${cx} ${points[i][1]}, ${cx} ${points[i + 1][1]}, ${points[i + 1][0]} ${points[i + 1][1]}`;
      }
      d += ` L 105 105 L -5 105 Z`;
      paths.push(d);
    }

    return paths;
  }

  import { matchFilters, type FilterResult } from '$lib/stores/content-filters.js';
  import { markSeen } from '$lib/utils/seen-posts.js';
  import AccountTypeIndicator from '$lib/components/ui/AccountTypeIndicator.svelte';
  import LazyMedia from '$lib/components/post/LazyMedia.svelte';
  import YouTubeEmbed from '$lib/components/post/YouTubeEmbed.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { parseYouTubeUrl, findYouTubeInContent } from '$lib/utils/youtube.js';
  import { focusedPostId } from '$lib/stores/focused-post.js';
  import { onMount, onDestroy } from 'svelte';

  let {
    post,
    compact = false,
    detail = false,
    filterContext = 'home',
    viewerContext = null,
  }: {
    post: Post;
    compact?: boolean;
    detail?: boolean;
    filterContext?: string;
    // Tells the card which feed it's being rendered into so it can
    // suppress the "Pinned" badge / Unpin menu entry when the post's
    // pin lives in a different scope. Subaccount profiles (groups,
    // pages, the parent user) are treated as separate profiles: a
    // group-pin should not read as a profile-pin on the parent
    // timeline, and vice versa. Leave null to keep the legacy
    // behaviour (badge shows wherever is_pinned is true) — only
    // pages that know their viewing context need to set this.
    viewerContext?: 'profile' | 'group' | 'page' | null;
  } = $props();

  // `is_pinned` is true on the post row; `pin_scope` (added in the
  // serializer) says where the pin actually applies. Treat the post
  // as "pinned here" only when the viewer is looking at the same
  // scope, otherwise the visual leak is exactly what made the user
  // try to unpin a group-pin from the profile feed.
  let pinnedHere = $derived(
    !!post.is_pinned &&
      (viewerContext === null ||
        post.pin_scope == null ||
        viewerContext === post.pin_scope),
  );

  let filterMatch: FilterResult | null = $derived(matchFilters(post.content, post.spoiler_text, filterContext));
  let filterRevealed = $state(false);
  let showSensitive = $state(false);

  let isFocused = $derived($focusedPostId === post.id);

  // The `x` shortcut maps to "toggle CW reveal" — handled here because
  // `showSensitive` is local card state. Other actions (reply / boost /
  // react) live in PostActions which has the relevant counters.
  onMount(() => {
    function handleShortcutAction(e: Event) {
      const detail = (e as CustomEvent<{ id: string; action: string }>).detail;
      if (!detail || detail.id !== post.id) return;
      if (detail.action === 'toggle-cw') {
        if (post.sensitive) {
          showSensitive = !showSensitive;
        } else if (filterMatch?.action === 'warn') {
          filterRevealed = !filterRevealed;
        }
      }
    }
    window.addEventListener('post-shortcut-action', handleShortcutAction);
    return () => window.removeEventListener('post-shortcut-action', handleShortcutAction);
  });
  // Hide the link-card image once the network reports it's bad. OG
  // `og:image` URLs go stale (404, hot-link blocked, deleted asset)
  // and the default <img> behaviour leaves a broken-image glyph in a
  // 2:1 box.
  let cardImageBroken = $state(false);
  // Prefer the link-card URL (already validated and previewed by the
  // backend) but fall back to scanning content — YouTube blocks our
  // OG fetcher often enough that `post.card` may be null even when a
  // valid YouTube URL is in the body.
  let youtubeRef = $derived(
    parseYouTubeUrl(post.card?.url ?? '') ?? findYouTubeInContent(post.content)
  );
  let contentCollapsed = $state(!detail);
  let contentOverflows = $state(false);
  let contentEl: HTMLDivElement | undefined = $state();

  let fullHeight = $state(0);
  const collapsedHeight = 248; // ~10 lines: 10 * 15px * 1.6 line-height + buffer

  // Check if content overflows 10 lines
  $effect(() => {
    if (contentEl && !detail) {
      fullHeight = contentEl.scrollHeight;
      contentOverflows = fullHeight > collapsedHeight;
      if (!contentOverflows) contentCollapsed = false;
    }
  });

  let timeAgo = $derived(relativeTime(post.created_at));
  let fullDate = $derived(fullDateTime(post.created_at));

  // Why an old post is sitting at the top of the feed: activity-ordered
  // timelines sort on `last_activity_at`, which only a reply bumps. Show
  // the bump's age so the ordering explains itself. Not on the detail
  // page — the replies themselves are right there. The one-minute floor
  // keeps it off posts whose own first-reply bump lands in the same
  // breath as publication.
  const BUMP_MIN_MS = 60_000;
  let bumpedAt = $derived.by(() => {
    if (detail || !post.last_activity_at || !post.reply_count) return null;
    const activity = new Date(post.last_activity_at).getTime();
    const created = new Date(post.created_at).getTime();
    if (!Number.isFinite(activity) || !Number.isFinite(created)) return null;
    return activity - created >= BUMP_MIN_MS ? post.last_activity_at : null;
  });

  // `relativeTime` is compact ("5m", "3h") and returns "now" under a
  // minute, which would read as "Last reply now ago" — so that case gets
  // its own phrase rather than an interpolation.
  let bumpLabel = $derived.by(() => {
    if (!bumpedAt) return null;
    const rel = relativeTime(bumpedAt);
    return rel === 'now' ? $t('post.last_reply_now') : $t('post.last_reply', { time: rel });
  });

  let avatarUrl = $derived(post.account.avatar_url || '');
  let displayName = $derived(post.account.display_name || post.account.acct || post.account.handle);
  let accountBadgeView = $derived(
    filterBadges(((post.account as { badges?: Badge[] }).badges) ?? [], !!post.account.is_verified),
  );
  let domain = $derived((post.account as any).domain as string | null);
  let isRemote = $derived(!!domain);
  // Prefer `acct` (already in webfinger form for remote accounts)
  // over our internal munged handle. A remote user like
  // `ahmad_bassamso_2e8909` renders as `@ahmad@example.social` —
  // what the user actually typed / expects to see.
  let handle = $derived('@' + (post.account.acct || post.account.handle));
  let instanceFavicon = $derived(domain ? `https://www.google.com/s2/favicons?domain=${domain}&sz=16` : null);

  // Media grid class based on count
  let mediaAttachments = $derived(post.media_attachments || []);
  let mediaCount = $derived(mediaAttachments.length);
  let mediaAllAudio = $derived(
    mediaCount > 0 && mediaAttachments.every((m) => m.type === 'audio')
  );
  let mediaGridClass = $derived(
    mediaAllAudio ? 'media-grid-1 media-grid-audio-only'
    : mediaCount === 1 ? 'media-grid-1'
    : mediaCount === 2 ? 'media-grid-2'
    : 'media-grid-4'
  );

  // Image lightbox: populated by an image click in the media grid.
  // Only images (not video/audio) open the lightbox — video has its
  // own inline <video controls>.
  //
  // Per-image reaction counts ride alongside each slide so the lightbox
  // can render the picker + count. We also keep a local override map
  // for the optimistic "I just reacted" state so the heart updates
  // without re-fetching the post. Override stores the chosen reaction
  // type (e.g. "like", "fire") plus the delta to apply to the count.
  let mediaReactionOverrides: Record<string, { currentReaction: string | null; delta: number }> =
    $state({});

  let lightboxImages = $derived(
    mediaAttachments
      .filter((m) => m.type === 'image' || m.type === 'gifv')
      .map((m) => {
        const baseCount = (post.media_reaction_counts as Record<string, number> | undefined)?.[m.id] ?? 0;
        const override = mediaReactionOverrides[m.id];
        return {
          id: m.id,
          url: m.url,
          alt: m.description,
          reactionCount: Math.max(0, baseCount + (override?.delta ?? 0)),
          currentReaction: override?.currentReaction ?? null,
        };
      })
  );
  let lightboxOpen = $state(false);
  let lightboxIndex = $state(0);

  // Separate state for the parent post's lightbox — opened when the
  // user clicks the "Replying to image #N" chip on a per-image
  // reply. Loads the parent post's media on demand so we don't do a
  // round-trip per reply on the feed.
  let parentLightboxOpen = $state(false);
  let parentLightboxIndex = $state(0);
  let parentLightboxImages = $state<
    Array<{ id: string; url: string; alt: string | null }>
  >([]);
  let parentLightboxLoading = $state(false);

  async function openParentLightbox() {
    if (!post.parent_id || !post.target_media_id) return;
    if (parentLightboxLoading) return;
    parentLightboxLoading = true;
    try {
      const parent = await getPost(post.parent_id);
      const images = (parent.media_attachments || [])
        .filter((m) => m.type === 'image' || m.type === 'gifv')
        .map((m) => ({ id: m.id, url: m.url, alt: m.description }));
      const idx = images.findIndex((s) => s.id === post.target_media_id);
      if (idx < 0 || images.length === 0) return;
      parentLightboxImages = images;
      parentLightboxIndex = idx;
      parentLightboxOpen = true;
    } catch {
      // Parent fetch failed — fall back to navigating to the post.
      // Use goto so SvelteKit can restore scroll on back-nav; a full
      // page reload throws the feed scroll position away.
      goto(`/post/${post.parent_id}`);
    } finally {
      parentLightboxLoading = false;
    }
  }

  async function handleMediaReact(mediaId: string, next: string | null) {
    const prev = mediaReactionOverrides[mediaId];
    const prevReaction = prev?.currentReaction ?? null;
    if (prevReaction === next) return;

    // Compute the count delta. Switching between two reactions doesn't
    // change the headline count (still one reaction from this user) —
    // only adding or removing does.
    let countDelta = 0;
    if (prevReaction === null && next !== null) countDelta = 1;
    else if (prevReaction !== null && next === null) countDelta = -1;

    mediaReactionOverrides = {
      ...mediaReactionOverrides,
      [mediaId]: {
        currentReaction: next,
        delta: (prev?.delta ?? 0) + countDelta,
      },
    };

    try {
      if (next === null) {
        await api.delete(`/api/v1/statuses/${post.id}/react`, {
          target_media_id: mediaId,
        });
      } else {
        // POST /react is upsert-style on the backend (existing reaction
        // updates its type), so switching from "like" to "fire"
        // doesn't need a DELETE first.
        await api.post(`/api/v1/statuses/${post.id}/react`, {
          type: next,
          target_media_id: mediaId,
        });
      }
    } catch {
      // Revert on failure.
      mediaReactionOverrides = {
        ...mediaReactionOverrides,
        [mediaId]: prev ?? { currentReaction: null, delta: 0 },
      };
    }
  }

  function openLightbox(media: typeof mediaAttachments[number]) {
    const idx = lightboxImages.findIndex((s) => s.url === media.url);
    if (idx < 0) return;
    lightboxIndex = idx;
    lightboxOpen = true;
  }

  function handleMediaClick(e: MouseEvent, media: typeof mediaAttachments[number]) {
    if (media.type !== 'image' && media.type !== 'gifv') return;
    // Stop the outer post-card click → post-detail navigation so
    // opening the image doesn't double as "go to post page".
    e.stopPropagation();
    e.preventDefault();
    openLightbox(media);
  }

  function handleMediaKey(e: KeyboardEvent, media: typeof mediaAttachments[number]) {
    if ((e.key === 'Enter' || e.key === ' ') && (media.type === 'image' || media.type === 'gifv')) {
      e.preventDefault();
      openLightbox(media);
    }
  }

  // Edit mode — full editor: content + media (add/remove) + NSFW
  // toggle + spoiler text + (when allowed) markdown toggle. Schedule
  // is intentionally absent: an existing post can't be re-scheduled.
  let editing = $state(false);
  let editContent = $state('');
  let editSaving = $state(false);
  let editError = $state('');
  let editSpoilerText = $state('');
  let editShowCW = $state(false);
  let editSensitive = $state(false);
  let editMedia = $state<MediaAttachment[]>([]);
  let editMediaUploading = $state(false);
  let editFileInputEl: HTMLInputElement | undefined = $state();
  // Per-tier media cap — read off the current user since the editor
  // owner is always the post's author. Defaults to 4 if limits aren't
  // populated yet (matches the composer's fallback).
  let editMediaMax = $derived($currentUser?.limits?.media_per_post ?? 4);
  // Markdown opt-down — same tier gate as the composer. Free-tier users
  // post plaintext by server policy and never see the toggle; markdown
  // tiers may opt a specific edit down to plain text via `markdown: false`,
  // which the backend honors in resolve_markdown_level. Defaults ON (parity
  // with the composer), so an editor must deliberately opt down.
  let editMarkdownLevel = $derived(($currentUser?.limits as { markdown?: string } | undefined)?.markdown ?? 'basic');
  let editCanMarkdown = $derived(!!editMarkdownLevel && editMarkdownLevel !== 'none');
  let editMarkdownEnabled = $state(true);

  function startEditing() {
    editContent = post.content || '';
    editSpoilerText = post.spoiler_text || '';
    editShowCW = !!(post.spoiler_text && post.spoiler_text.length > 0);
    editSensitive = !!post.sensitive;
    editMedia = [...(post.media_attachments || [])];
    editMarkdownEnabled = true;
    editError = '';
    editing = true;
  }

  async function uploadEditFiles(files: File[]) {
    if (files.length === 0) return;

    const remaining = editMediaMax - editMedia.length;
    if (remaining <= 0) {
      editError = `Maximum ${editMediaMax} media attachments allowed`;
      return;
    }

    const toUpload = files.slice(0, remaining);
    editMediaUploading = true;
    editError = '';
    try {
      const results = await Promise.allSettled(toUpload.map((f) => uploadMedia(f)));
      const succeeded: MediaAttachment[] = [];
      let firstErr = '';
      for (const r of results) {
        if (r.status === 'fulfilled') {
          succeeded.push(r.value);
        } else {
          if (!firstErr) {
            const body = (r.reason as { body?: { error?: string } })?.body;
            firstErr = body?.error || translate('post.upload_failed');
          }
        }
      }
      if (succeeded.length > 0) editMedia = [...editMedia, ...succeeded];
      if (firstErr) editError = firstErr;
    } finally {
      editMediaUploading = false;
    }
  }

  async function handleEditFileSelected(e: Event) {
    const input = e.target as HTMLInputElement;
    const files = Array.from(input.files ?? []);
    input.value = '';
    await uploadEditFiles(files);
  }

  // Drag & drop parity with the composer — dropping media onto the edit
  // dialog uploads it (the dialog previously ignored drops entirely).
  function handleEditDragOver(e: DragEvent) {
    e.preventDefault();
  }

  function handleEditDrop(e: DragEvent) {
    e.preventDefault();
    const files = Array.from(e.dataTransfer?.files ?? []);
    if (files.length > 0) uploadEditFiles(files);
  }

  function removeEditMedia(id: string) {
    editMedia = editMedia.filter((m) => m.id !== id);
  }

  async function saveEdit() {
    if (!editContent.trim() && editMedia.length === 0) return;
    editSaving = true;
    editError = '';
    try {
      const updated = await editPost(post.id, {
        content: editContent,
        sensitive: editSensitive || (editShowCW && !!editSpoilerText.trim()),
        spoiler_text: editShowCW ? editSpoilerText : '',
        media_ids: editMedia.map((m) => m.id),
        // Opt this edit down to plain text (tier default is otherwise applied
        // server-side, which would re-interpret ** / # on every edit).
        ...(editCanMarkdown && !editMarkdownEnabled ? { markdown: false } : {}),
      });
      post.content = updated.content;
      post.content_html = updated.content_html;
      post.edited_at = updated.edited_at;
      post.spoiler_text = updated.spoiler_text;
      post.sensitive = updated.sensitive;
      post.media_attachments = updated.media_attachments;
      editing = false;
    } catch {
      editError = translate('post.edit_save_failed');
    } finally {
      editSaving = false;
    }
  }

  function cancelEdit() {
    editing = false;
    editError = '';
  }

  // Hashtag footer: if the post ends with a run of hashtag-only
  // content, strip those from the body and surface ALL tags (trailing
  // or inline) as pill buttons under the post. The dependency on
  // `post.content_html` is intentional — re-runs after an edit.
  let displayContentHtml = $derived.by(() => {
    const raw = post.content_html ?? '';
    // Strip the trailing-hashtag footer first (gets surfaced as pills
    // below the post), then swap any :shortcode: text for the
    // matching <img> from the per-post emoji manifest. Doing emojis
    // after the hashtag pass means we don't accidentally drop an
    // emoji that lives next to a trailing hashtag.
    const stripped =
      !post.tags || post.tags.length === 0 ? raw : stripTrailingHashtags(raw).html;
    return renderCustomEmojis(stripped, post.emojis);
  });

  // --- Post translation ---
  // The translated body (plain text) is fetched lazily on first click and
  // cached, so toggling back and forth doesn't re-hit the backend.
  let translatedText = $state<string | null>(null);
  let translationProvider = $state('');
  let translating = $state(false);
  let showingTranslation = $state(false);

  // The language we'd translate INTO, resolved to a display name for the
  // button label ("Translate to العربية"). Follows the user's Settings choice,
  // falling back to the interface language.
  let translateTargetName = $derived.by(() => {
    const code = $effectiveTranslationTarget;
    const meta = $availableLocales.find((l) => l.code === code);
    return meta?.nativeName || meta?.name || code.toUpperCase();
  });

  // Offer translation only when the instance has a backend configured, the post
  // has text, and it isn't already in the target language (when the source is
  // known). The endpoint enforces the backend gate server-side regardless.
  let canTranslate = $derived(
    $translationEnabled &&
      !!(post.content || post.content_html) &&
      post.language !== $effectiveTranslationTarget,
  );

  async function handleTranslateToggle(e: MouseEvent) {
    e.stopPropagation();
    if (showingTranslation) {
      showingTranslation = false;
      return;
    }
    if (translatedText !== null) {
      showingTranslation = true;
      return;
    }
    translating = true;
    try {
      const res = await translateStatus(post.id, $effectiveTranslationTarget);
      translatedText = res.content;
      translationProvider = res.provider;
      showingTranslation = true;
    } catch {
      addToast($t('post.translate_failed'), 'error');
    } finally {
      translating = false;
    }
  }

  // Poll voting
  let pollVoted = $state(post.poll?.voted ?? false);
  let pollOwnVotes = $state<number[]>(post.poll?.own_votes ?? []);
  let pollOptions = $state(post.poll?.options ?? []);
  let pollVotesCount = $state(post.poll?.votes_count ?? 0);
  let pollVotersCount = $state(post.poll?.voters_count ?? 0);
  let pollExpired = $state(post.poll?.expired ?? false);
  let pollVoting = $state(false);

  // Pending-vote state: while not null, a vote has been selected but
  // not yet sent to the server. The countdown ticks down from
  // COUNTDOWN_SECONDS; clicking another option resets it. Holding the
  // submit lets the user undo a misclick before any federation
  // happens. We block in-app navigation while this is non-null so the
  // user can't accidentally walk away from a vote that's about to go
  // out (or stays unsubmitted forever).
  const COUNTDOWN_SECONDS = 5;
  let pendingVoteOptions = $state<number[] | null>(null);
  let countdownRemaining = $state(COUNTDOWN_SECONDS);
  let countdownTimer: ReturnType<typeof setInterval> | null = null;

  let showPollResults = $derived(pollVoted || pollExpired || pendingVoteOptions !== null);

  // The user's effective choice for rendering: the locked-in own_votes
  // once committed, or the pending selection while the countdown is
  // still running.
  let displayOwnVotes = $derived(pendingVoteOptions ?? pollOwnVotes);

  // Optimistic vote counts so the user sees their vote land in the
  // bars immediately. Once the server confirms, pollOptions /
  // pollVotesCount are overwritten with authoritative values.
  let displayVotesTotal = $derived(
    pendingVoteOptions ? pollVotesCount + pendingVoteOptions.length : pollVotesCount,
  );

  function startOrResetCountdown() {
    countdownRemaining = COUNTDOWN_SECONDS;
    if (countdownTimer) clearInterval(countdownTimer);
    countdownTimer = setInterval(() => {
      countdownRemaining -= 1;
      if (countdownRemaining <= 0) {
        finishCountdown();
      }
    }, 1000);
  }

  function clearCountdownTimer() {
    if (countdownTimer) {
      clearInterval(countdownTimer);
      countdownTimer = null;
    }
  }

  function cancelPendingVote(e?: Event) {
    e?.stopPropagation();
    clearCountdownTimer();
    pendingVoteOptions = null;
    countdownRemaining = COUNTDOWN_SECONDS;
  }

  async function finishCountdown() {
    clearCountdownTimer();
    if (!post.poll || !pendingVoteOptions || pendingVoteOptions.length === 0) {
      pendingVoteOptions = null;
      return;
    }
    const choices = pendingVoteOptions;
    pendingVoteOptions = null;
    pollVoting = true;
    try {
      const result = await api.post<typeof post.poll>(`/api/v1/polls/${post.poll.id}/votes`, {
        choices,
      });
      pollVoted = true;
      pollOwnVotes = result.own_votes;
      pollOptions = result.options;
      pollVotesCount = result.votes_count;
      pollVotersCount = result.voters_count;
      pollExpired = result.expired;
    } catch {
      // Restore the selection so the user can either retry or cancel
      // explicitly. Counts aren't bumped on the server, so optimistic
      // numbers are fine to show again.
      pendingVoteOptions = choices;
      countdownRemaining = COUNTDOWN_SECONDS;
    } finally {
      pollVoting = false;
    }
  }

  function handlePollOptionClick(index: number, e: Event) {
    e.stopPropagation();
    if (pollVoted || pollExpired || pollVoting) return;
    if (post.poll?.multiple) {
      const current = pendingVoteOptions ?? [];
      const next = current.includes(index)
        ? current.filter((i) => i !== index)
        : [...current, index];
      if (next.length === 0) {
        cancelPendingVote();
        return;
      }
      pendingVoteOptions = next;
    } else {
      pendingVoteOptions = [index];
    }
    startOrResetCountdown();
  }

  // Block in-app navigation while a vote is pending. Letting the user
  // walk away would either silently drop the vote or surface it later
  // with no clear feedback — both worse than a one-line nudge to
  // either cancel or wait.
  beforeNavigate((nav) => {
    if (pendingVoteOptions !== null && nav.cancel) {
      nav.cancel();
      window.dispatchEvent(
        new CustomEvent('toast', {
          detail: {
            message: translate('poll.pending_vote_warning'),
            type: 'warning',
          },
        }),
      );
    }
  });

  // Tab close / hard reload while a vote is pending: trigger the
  // browser's native confirm. We can't customise the message, but the
  // prompt itself is enough to stop accidental closes.
  $effect(() => {
    if (pendingVoteOptions === null) return;
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  });

  // Don't leave a setInterval running after the card unmounts (feed
  // reshuffle, route change with the card off-screen, etc.) — the
  // beforeNavigate gate covers same-app navigation, but a feed
  // teardown can still drop the component while the timer is live.
  onDestroy(() => {
    clearCountdownTimer();
  });

  // Poll voters modal — lists who voted but not what they chose, per
  // privacy-of-vote rule. Loaded on demand the first time the modal
  // opens and cached for the lifetime of this card.
  type PollVoter = {
    id: string;
    handle: string;
    acct: string;
    display_name: string | null;
    avatar_url: string | null;
    url: string | null;
  };
  let votersOpen = $state(false);
  let votersLoading = $state(false);
  let voters = $state<PollVoter[] | null>(null);

  async function openVoters(e: MouseEvent) {
    e.stopPropagation();
    votersOpen = true;
    if (voters !== null || !post.poll) return;
    votersLoading = true;
    try {
      const res = await api.get<{ voters: PollVoter[]; total: number }>(
        `/api/v1/polls/${post.poll.id}/voters`,
      );
      voters = res.voters || [];
    } catch {
      voters = [];
    } finally {
      votersLoading = false;
    }
  }


  function navigateToPost() {
    markSeen(post.id);
    // SPA navigate so the browser keeps the previous page (and its
    // scroll position) in history. `window.location.href` triggers a
    // full reload, after which SvelteKit's scroll restoration has
    // nothing to restore — the feed snaps to the top on back.
    goto(`/post/${post.id}`);
  }

  function handleCardClick(e: MouseEvent) {
    if (detail) return;
    const selection = window.getSelection();
    if (selection && selection.toString().length > 0) return;
    const target = e.target as HTMLElement;
    if (target.closest('a, button, [role="button"], video, audio, textarea, select, input')) return;
    navigateToPost();
  }

  function handleCardKeydown(e: KeyboardEvent) {
    if (detail) return;
    if (e.key === 'Enter' || e.key === ' ') {
      const target = e.target as HTMLElement;
      if (target.closest('a, button, [role="button"], textarea, select, input')) return;
      e.preventDefault();
      navigateToPost();
    }
  }
</script>

{#if post.tombstone}
<article class="post-card post-tombstone" role="article">
  <div class="tombstone-content">
    <span class="material-symbols-outlined tombstone-icon">delete</span>
    <p class="tombstone-text">{$t('post.deleted')}</p>
  </div>
</article>
{:else}
<article
  class="post-card"
  class:compact
  class:detail
  class:post-card-pending={post.pending}
  class:post-card-focused={isFocused && !detail}
  aria-busy={post.pending ? 'true' : undefined}
  role="article"
  tabindex={detail ? -1 : 0}
  onclick={handleCardClick}
  onkeydown={handleCardKeydown}
  aria-label={$t('post.post_by_aria', { name: displayName })}
>
  <div class="post-layout">
    <!-- Avatar column -->
    <div class="post-avatar">
      <img src={avatarUrl || '/images/default-avatar.svg'} alt="" class="avatar-img" loading="lazy" />
    </div>

    <!-- Content column -->
    <div class="post-content-col">
      {#if pinnedHere}
        {@const pinTitle = post.group
          ? $t('post.pinned_in_named', { name: post.group.name })
          : post.page
            ? $t('post.pinned_on_named', { name: post.page.name })
            : $t('post.pinned_profile')}
        <div class="post-pinned-indicator" title={pinTitle}>
          <span class="material-symbols-outlined pinned-icon" aria-hidden="true">push_pin</span>
          <span>{$t('post.pinned_badge')}</span>
        </div>
      {/if}
      <div class="post-author-line">
        <div class="post-author-info">
          <div class="post-author-name-row">
            <ProfileHoverCard handle={post.account.acct || post.account.handle}>
              <a href="/@{post.account.handle}" class="post-display-name"><DisplayName name={displayName} emojis={post.account.emojis} /></a>
            </ProfileHoverCard>
            {#if accountBadgeView.showVerifiedMark}
              <VerifiedBadge size="sm" />
            {/if}
            <AccountTypeIndicator account={post.account} />
            {#each accountBadgeView.nonTier as badge (badge.type)}
              <RoleBadge type={badge.type} label={badge.label} size="sm" />
            {/each}
            {#if accountBadgeView.highestTier}
              <RoleBadge type={accountBadgeView.highestTier.type} label={accountBadgeView.highestTier.label} size="sm" />
            {/if}
          </div>
          <div class="post-meta-row">
            <span class="post-handle">{handle}</span>
            {#if instanceFavicon}
              <img src={instanceFavicon} alt={domain} class="instance-favicon" loading="lazy" />
            {/if}
            <span class="post-dot" aria-hidden="true">&middot;</span>
            <a
              class="post-time-link"
              href="/post/{post.id}"
              onclick={(e) => e.stopPropagation()}
            >
              <time class="post-time" datetime={post.created_at} title={fullDate}>{timeAgo}</time>
            </a>
            {#if post.edited_at}
              <span class="post-edited" title={$t('post.edited_at_title', { date: fullDateTime(post.edited_at) })}>{$t('post.edited_marker')}</span>
            {/if}
            {#if post.pending}
              <span class="post-pending-badge" aria-live="polite">
                <span class="spinner" aria-hidden="true"></span>
                {$t('post.posting')}
              </span>
            {/if}
          </div>
          {#if bumpedAt && bumpLabel}
            <div class="post-bump-row">
              <span class="post-bump" title={fullDateTime(bumpedAt)}>{bumpLabel}</span>
            </div>
          {/if}
        </div>
        {#if $isStaffMember}
          <AdminPostActions {post} />
        {/if}
      </div>

      {#if (post as any).group}
        {@const g = (post as any).group}
        <a class="post-scope-chip" href={`/groups/${g.id}`} onclick={(e) => e.stopPropagation()}>
          <span class="material-symbols-outlined" aria-hidden="true">groups</span>
          <span class="post-scope-label">{$t('post.posted_in')} <strong>{g.name}</strong></span>
        </a>
      {:else if (post as any).page}
        {@const p = (post as any).page}
        <a class="post-scope-chip" href={`/pages/${p.id}`} onclick={(e) => e.stopPropagation()}>
          <span class="material-symbols-outlined" aria-hidden="true">description</span>
          <span class="post-scope-label">{$t('post.posted_on')} <strong>{p.name}</strong></span>
        </a>
      {/if}

      {#if post.parent_id}
        <div class="post-reply-indicator">
          <span class="material-symbols-outlined reply-icon" aria-hidden="true">reply</span>
          {#if post.target_media_id}
            <button
              type="button"
              class="reply-target-media"
              onclick={(e) => { e.stopPropagation(); openParentLightbox(); }}
              disabled={parentLightboxLoading}
              aria-label={post.target_media_index
                ? $t('post.open_image_n', { n: post.target_media_index })
                : $t('post.open_targeted_image')}
            >
              {#if post.target_media_preview_url}
                <img class="reply-target-thumb" src={post.target_media_preview_url} alt="" />
              {/if}
              <span>
                {post.target_media_index
                  ? $t('post.replying_to_image_n', { n: post.target_media_index })
                  : $t('post.replying_to_specific_image')}
              </span>
            </button>
          {:else if post.in_reply_to_account_id}
            <span>{$t('post.replying_to')} <a href="/post/{post.parent_id}" class="reply-to-link">{$t('post.a_post')}</a></span>
          {:else}
            <span>{$t('post.replying_to_post')}</span>
          {/if}
        </div>
      {/if}

      <!-- Content filter warning -->
      {#if filterMatch?.action === 'warn' && !filterRevealed}
        <div class="filter-warning">
          <span class="material-symbols-outlined filter-icon">filter_alt</span>
          <span class="filter-text">{$t('post.filtered')} <strong>{filterMatch.filter.phrase}</strong></span>
          <button class="filter-reveal-btn" type="button" onclick={() => filterRevealed = true}>{$t('post.show_anyway')}</button>
        </div>
      {/if}

      <!-- Post body -->
      <div class="post-body" class:filter-hidden={filterMatch?.action === 'warn' && !filterRevealed}>
        <div class="nsfw-container" class:nsfw-active={post.sensitive} class:nsfw-revealed={showSensitive}>
          <div class="nsfw-content">
          {#if showingTranslation && translatedText !== null}
            <div class="post-content" dir="auto">
              {#each translatedText.split('\n') as line, i (i)}
                {#if line}<p dir="auto">{line}</p>{/if}
              {/each}
            </div>
          {:else if post.content_html}
            <div
              class="post-content"
              class:post-content-collapsed={contentCollapsed && contentOverflows}
              style={contentOverflows ? `max-height: ${contentCollapsed ? collapsedHeight : fullHeight}px` : ''}
              bind:this={contentEl}
              dir="auto"
            >
              {@html displayContentHtml}
            </div>
          {:else if post.content}
            <div
              class="post-content"
              class:post-content-collapsed={contentCollapsed && contentOverflows}
              style={contentOverflows ? `max-height: ${contentCollapsed ? collapsedHeight : fullHeight}px` : ''}
              bind:this={contentEl}
              dir="auto"
            >
              <p dir="auto">{post.content}</p>
            </div>
          {/if}
          {#if !showingTranslation && contentOverflows && contentCollapsed}
            <button type="button" class="content-toggle-btn" onclick={(e) => { e.stopPropagation(); contentCollapsed = false; }}>
              <span class="material-symbols-outlined content-toggle-icon">expand_more</span>
              {$t('post.show_more')}
            </button>
          {/if}
          {#if !showingTranslation && contentOverflows && !contentCollapsed && !detail}
            <button type="button" class="content-toggle-btn content-toggle-collapse" onclick={(e) => { e.stopPropagation(); contentCollapsed = true; }}>
              <span class="material-symbols-outlined content-toggle-icon">expand_less</span>
              {$t('post.show_less')}
            </button>
          {/if}

          {#if canTranslate}
            <div class="translate-row" onclick={(e) => e.stopPropagation()} role="presentation">
              <button type="button" class="translate-btn" onclick={handleTranslateToggle} disabled={translating}>
                <span class="material-symbols-outlined translate-icon">translate</span>
                {#if translating}
                  {$t('post.translating')}
                {:else if showingTranslation}
                  {$t('post.show_original')}
                {:else}
                  {$t('post.translate_to', { lang: translateTargetName })}
                {/if}
              </button>
              {#if showingTranslation && translationProvider}
                <span class="translate-provider">{$t('post.translated_via', { provider: translationProvider })}</span>
              {/if}
            </div>
          {/if}

          {#if post.tags && post.tags.length > 0}
            <div class="hashtag-footer" onclick={(e) => e.stopPropagation()} role="group" aria-label={$t('post.hashtags_aria')}>
              {#each post.tags as tag (tag.name)}
                <a
                  href="/tags/{encodeURIComponent(tag.name)}"
                  class="hashtag-chip"
                  onclick={(e) => e.stopPropagation()}
                >#{tag.name}</a>
              {/each}
            </div>
          {/if}

          {#if mediaCount > 0 && !compact}
            <div class="media-grid {mediaGridClass}">
              {#each mediaAttachments as media (media.id)}
                {@const clickable = media.type === 'image' || media.type === 'gifv'}
                <div
                  class="media-item"
                  class:media-audio={media.type === 'audio'}
                  class:media-video-cell={media.type === 'video'}
                  class:media-clickable={clickable}
                  role={clickable ? 'button' : undefined}
                  tabindex={clickable ? 0 : undefined}
                  onclick={(e) => handleMediaClick(e, media)}
                  onkeydown={(e) => handleMediaKey(e, media)}
                  aria-label={clickable ? (media.description || $t('post.open_image')) : undefined}
                >
                  <LazyMedia {media} isRemote={!!media.remote_url} author={post.account} />
                </div>
              {/each}
            </div>
          {/if}

          {#if post.poll && !compact}
            <div class="post-poll">
              {#each pollOptions as option, i (i)}
                {@const optimisticCount = option.votes_count + (pendingVoteOptions?.includes(i) ? 1 : 0)}
                {@const pct = displayVotesTotal > 0 ? Math.round(optimisticCount / displayVotesTotal * 100) : 0}
                {#if showPollResults}
                  <div class="poll-result-row" class:poll-result-mine={displayOwnVotes.includes(i)}>
                    <div class="poll-result-header">
                      <span class="poll-result-title">
                        {#if displayOwnVotes.includes(i)}
                          <span class="poll-voted-check" aria-label={$t('poll.your_vote')}>&#10003;</span>
                        {/if}
                        {option.title}
                      </span>
                      <span class="poll-result-pct">{pct}%</span>
                    </div>
                    <div class="poll-result-track" aria-hidden="true">
                      <div
                        class="poll-result-fill"
                        class:poll-result-fill-mine={displayOwnVotes.includes(i)}
                        style="width: {pct}%"
                      ></div>
                    </div>
                  </div>
                {:else}
                  <button
                    type="button"
                    class="poll-option poll-votable"
                    onclick={(e) => handlePollOptionClick(i, e)}
                  >
                    <span class="poll-check-indicator">
                      {#if post.poll?.multiple}&#9633;{:else}&#9675;{/if}
                    </span>
                    <span class="poll-label">{option.title}</span>
                  </button>
                {/if}
              {/each}

              {#if pendingVoteOptions !== null}
                <button
                  type="button"
                  class="poll-cancel-btn"
                  onclick={cancelPendingVote}
                >
                  <span class="material-symbols-outlined poll-cancel-icon">undo</span>
                  {$t('poll.cancel_vote', { seconds: countdownRemaining })}
                </button>
              {/if}

              <div class="poll-info">
                {#if pollVotersCount > 0}
                  <button
                    type="button"
                    class="poll-voters-link"
                    onclick={openVoters}
                    aria-label={$t('poll.view_voters')}
                  >
                    {$t('poll.votes', { count: displayVotesTotal })}
                  </button>
                {:else}
                  {$t('poll.votes', { count: displayVotesTotal })}
                {/if}
                {#if pollExpired}
                  &middot; {$t('poll.ended')}
                {:else if post.poll.expires_at}
                  &middot; {$t('poll.ends', { time: relativeTimeFuture(post.poll.expires_at) })}
                {/if}
              </div>
            </div>
          {/if}

          {#if votersOpen}
            <Modal bind:open={votersOpen} title={$t('poll.voters')}>
              {#if votersLoading}
                <div class="voters-loading">{$t('common.loading')}</div>
              {:else if !voters || voters.length === 0}
                <div class="voters-empty">{$t('poll.no_voters')}</div>
              {:else}
                <ul class="voters-list">
                  {#each voters as v (v.id)}
                    <li class="voter-row">
                      <a
                        class="voter-link"
                        href={`/@${v.acct || v.handle}`}
                        onclick={(e) => { e.stopPropagation(); votersOpen = false; }}
                      >
                        <img
                          class="voter-avatar"
                          src={v.avatar_url || '/images/default-avatar.svg'}
                          alt=""
                          loading="lazy"
                        />
                        <span class="voter-name">{v.display_name || v.handle}</span>
                        <span class="voter-handle">@{v.acct || v.handle}</span>
                      </a>
                    </li>
                  {/each}
                </ul>
              {/if}
            </Modal>
          {/if}

          {#if post.quote && !compact}
            <QuoteCard post={post.quote} />
          {/if}

          {#if youtubeRef && !compact && mediaAttachments.length === 0}
            <YouTubeEmbed ref={youtubeRef} title={post.card?.title ?? ''} />
          {:else if post.card && !compact && mediaAttachments.length === 0}
            <a href={post.card.url} class="link-card" target="_blank" rel="noopener noreferrer" onclick={(e) => e.stopPropagation()}>
              {#if post.card.image && !cardImageBroken}
                <div class="link-card-image">
                  <img
                    src={post.card.image}
                    alt=""
                    loading="lazy"
                    onerror={() => (cardImageBroken = true)}
                  />
                </div>
              {/if}
              <div class="link-card-body">
                {#if post.card.provider_name}
                  <span class="link-card-provider">{post.card.provider_name}</span>
                {/if}
                {#if post.card.title}
                  <span class="link-card-title">{post.card.title}</span>
                {/if}
                {#if post.card.description}
                  <span class="link-card-desc">{post.card.description}</span>
                {/if}
              </div>
            </a>
          {/if}
          </div>

          {#if post.sensitive}
            {@const wavePaths = generateWavePaths(post.id)}
            <svg class="nsfw-noise-svg" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" preserveAspectRatio="none">
              <defs>
                <linearGradient id="nsfw-grad-{post.id}" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="var(--color-primary)" stop-opacity="0.15" />
                  <stop offset="50%" stop-color="var(--color-primary)" stop-opacity="0.4" />
                  <stop offset="100%" stop-color="var(--color-primary)" stop-opacity="0.7" />
                </linearGradient>
              </defs>
              <rect width="100" height="100" fill="var(--color-primary)" opacity="0.08" />
              {#each wavePaths as d, i (i)}
                {@const rng2 = seededRng(post.id + '-anim-' + i)}
                {@const drift = 2 + rng2() * 3}
                {@const dur = 7 + rng2() * 9}
                {@const delay = rng2() * -dur}
                {@const driftX = 1 + rng2() * 2}
                {@const durX = 9 + rng2() * 12}
                {@const delayX = rng2() * -durX}
                <g opacity={0.08 + i * 0.07}>
                  <animateTransform
                    attributeName="transform"
                    type="translate"
                    values="0,0; {driftX},{drift}; -{driftX},0; 0,-{drift}; 0,0"
                    dur="{dur}s"
                    begin="{delay}s"
                    repeatCount="indefinite"
                    calcMode="spline"
                    keySplines="0.45 0.05 0.55 0.95; 0.45 0.05 0.55 0.95; 0.45 0.05 0.55 0.95; 0.45 0.05 0.55 0.95"
                  />
                  <path
                    {d}
                    fill="var(--color-primary)"
                  />
                </g>
              {/each}
            </svg>
            <div class="nsfw-frost-glass"></div>
            <div class="nsfw-overlay" onclick={(e) => e.stopPropagation()}>
              <span class="nsfw-badge">NSFW</span>
              <p class="nsfw-warning">
                {post.spoiler_text && post.spoiler_text !== 'true'
                  ? post.spoiler_text
                  : $t('post.nsfw_warning')}
              </p>
              <button
                type="button"
                class="nsfw-reveal-btn"
                onclick={(e) => { e.stopPropagation(); showSensitive = true; }}
              >
                {$t('post.show_content')}
              </button>
            </div>
            <button
              type="button"
              class="nsfw-hide-btn"
              onclick={(e) => { e.stopPropagation(); showSensitive = false; contentCollapsed = true; }}
            >
              {$t('post.hide_content')}
            </button>
          {/if}
        </div>
      </div>

      {#if !compact}
        <div class="post-actions-divider"></div>
        <PostActions {post} {viewerContext} onedit={startEditing} />
      {/if}
    </div>
  </div>
</article>
{/if}

{#if lightboxOpen && lightboxImages.length > 0}
  <ImageLightbox
    images={lightboxImages}
    bind:index={lightboxIndex}
    postId={post.id}
    onclose={() => (lightboxOpen = false)}
    onreply={(mediaId, mediaIndex) => {
      lightboxOpen = false;
      window.dispatchEvent(
        new CustomEvent('open-composer', {
          detail: {
            replyTo: post,
            targetMediaId: mediaId,
            targetMediaIndex: mediaIndex,
          },
        }),
      );
    }}
    onreact={handleMediaReact}
  />
{/if}

{#if parentLightboxOpen && parentLightboxImages.length > 0}
  <ImageLightbox
    images={parentLightboxImages}
    bind:index={parentLightboxIndex}
    postId={post.parent_id ?? undefined}
    onclose={() => (parentLightboxOpen = false)}
  />
{/if}

{#if editing}
  <div class="edit-overlay" onclick={cancelEdit} role="dialog" aria-modal="true" aria-label={$t('post.edit_post')}>
    <div class="edit-dialog" onclick={(e) => e.stopPropagation()} ondragover={handleEditDragOver} ondrop={handleEditDrop}>
      <div class="edit-dialog-header">
        <h3 class="edit-dialog-title">{$t('post.edit_post')}</h3>
        <button type="button" class="edit-dialog-close" onclick={cancelEdit} aria-label={$t('common.close')}>
          <span class="material-symbols-outlined">close</span>
        </button>
      </div>

      {#if editShowCW}
        <input
          type="text"
          class="edit-cw-input"
          bind:value={editSpoilerText}
          placeholder={$t('post.cw_placeholder')}
          aria-label={$t('post.content_warning')}
          dir="auto"
        />
      {/if}

      <textarea
        class="edit-textarea"
        bind:value={editContent}
        rows="6"
        aria-label={$t('post.edit_content_aria')}
        dir="auto"
        autofocus
      ></textarea>

      {#if editMedia.length > 0}
        <div class="edit-media-grid">
          {#each editMedia as m (m.id)}
            <div class="edit-media-item">
              {#if m.type === 'image'}
                <img src={m.preview_url || m.url} alt={m.description || ''} class="edit-media-preview" loading="lazy" />
              {:else if m.type === 'video' || m.type === 'gifv'}
                <video src={m.url} class="edit-media-preview" muted></video>
              {:else if m.type === 'audio'}
                <div class="edit-media-audio">
                  <span class="material-symbols-outlined">music_note</span>
                  {$t('media.audio')}
                </div>
              {:else}
                <div class="edit-media-other">{m.type || $t('media.file')}</div>
              {/if}
              <button
                type="button"
                class="edit-media-remove"
                onclick={() => removeEditMedia(m.id)}
                aria-label={$t('post.remove_attachment')}
                title={$t('post.remove_attachment')}
              >
                <span class="material-symbols-outlined">close</span>
              </button>
            </div>
          {/each}
        </div>
      {/if}

      <input
        type="file"
        bind:this={editFileInputEl}
        onchange={handleEditFileSelected}
        accept="image/*,video/*,audio/*"
        multiple
        style="display: none;"
      />

      <div class="edit-toolbar">
        <button
          type="button"
          class="edit-tool"
          onclick={() => editFileInputEl?.click()}
          disabled={editMedia.length >= editMediaMax || editMediaUploading}
          aria-label={$t('post.attach_media')}
          title={editMedia.length >= editMediaMax
            ? $t('post.max_attachments', { max: editMediaMax })
            : $t('post.attach_hint', { max: editMediaMax })}
        >
          <span class="material-symbols-outlined">image</span>
        </button>

        <button
          type="button"
          class="edit-tool"
          class:edit-tool-active={editShowCW}
          onclick={() => (editShowCW = !editShowCW)}
          aria-pressed={editShowCW}
          aria-label={$t('post.toggle_cw')}
          title={editShowCW ? $t('post.remove_cw') : $t('post.add_cw')}
        >
          CW
        </button>

        <button
          type="button"
          class="edit-tool"
          class:edit-tool-active={editSensitive}
          onclick={() => (editSensitive = !editSensitive)}
          aria-pressed={editSensitive}
          aria-label={$t('post.mark_sensitive_aria')}
          title={editSensitive
            ? $t('post.unmark_sensitive_title')
            : $t('post.mark_sensitive_title')}
        >
          NSFW
        </button>

        {#if editCanMarkdown}
          <!-- Markdown opt-down, tier-gated (mirrors the composer). When
               off, this edit is stored and rendered as plain text even if
               the body contains ** or # characters. -->
          <button
            type="button"
            class="edit-tool"
            class:edit-tool-active={editMarkdownEnabled}
            onclick={() => (editMarkdownEnabled = !editMarkdownEnabled)}
            aria-pressed={editMarkdownEnabled}
            aria-label={$t('post.edit_markdown_label')}
            title={editMarkdownEnabled
              ? $t('post.edit_markdown_on')
              : $t('post.edit_markdown_off')}
          >
            MD
          </button>
        {/if}

        {#if editMediaUploading}
          <span class="edit-uploading">{$t('post.uploading')}</span>
        {/if}
      </div>

      {#if editError}
        <p class="edit-error">{editError}</p>
      {/if}

      <div class="edit-dialog-actions">
        <button type="button" class="edit-cancel" onclick={cancelEdit}>{$t('common.cancel')}</button>
        <button
          type="button"
          class="edit-save"
          onclick={saveEdit}
          disabled={editSaving || (!editContent.trim() && editMedia.length === 0)}
        >
          {editSaving ? $t('post.saving') : $t('common.save')}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .post-card {
    position: relative;
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: 24px;
    cursor: pointer;
    /* Layered ambient elevation — a crisp contact shadow plus a soft
       wide ambient. Reads premium on the mint wash instead of the old
       single harsh drop shadow. */
    box-shadow:
      0 1px 2px rgba(25, 28, 29, 0.04),
      0 6px 20px rgba(25, 28, 29, 0.05);
    transition:
      box-shadow 220ms ease,
      transform 220ms ease,
      border-color 220ms ease;
    user-select: text;
  }

  .post-card.detail {
    cursor: default;
  }

  .post-tombstone {
    cursor: default;
    opacity: 0.6;
    padding: 16px 24px;
  }

  .post-tombstone:hover {
    background: var(--color-surface-container-lowest);
  }

  /* Optimistic post — rendered immediately on submit, swapped out
     once the server responds. Faded body + a subtle pulse so users
     know the post hasn't fully committed yet. */
  .post-card-pending {
    opacity: 0.55;
    animation: post-pending-pulse 1.4s ease-in-out infinite;
    pointer-events: none;
  }

  /* Keyboard cursor highlight: a left-side accent so j/k position is
     unmistakable but the rest of the card stays visually unchanged. */
  .post-card-focused {
    box-shadow: inset 3px 0 0 var(--color-primary);
  }

  @keyframes post-pending-pulse {
    0%, 100% { opacity: 0.55; }
    50% { opacity: 0.8; }
  }

  .post-pending-badge {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--color-text-tertiary);
    margin-inline-start: 6px;
  }

  .post-pending-badge .spinner {
    width: 10px;
    height: 10px;
    border: 1.5px solid var(--color-border);
    border-top-color: var(--color-primary);
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
    display: inline-block;
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  .tombstone-content {
    display: flex;
    align-items: center;
    gap: 10px;
    color: var(--color-text-tertiary);
  }

  .tombstone-icon {
    font-size: 20px;
  }

  .tombstone-text {
    font-size: 0.875rem;
    font-style: italic;
  }

  /* Feed cards lift with a brand-tinted glow on hover so the whole
     timeline feels alive and each card reads as clickable. Background
     stays white (no graying). Detail view + tombstones opt out. */
  .post-card:hover {
    transform: translateY(-2px);
    /* Lift the hovered card above its siblings. The hover transform
       creates a stacking context, which otherwise traps an open action
       dropdown *below* the next card (making it unclickable). */
    z-index: 5;
    box-shadow:
      0 2px 4px rgba(25, 28, 29, 0.05),
      0 4px 14px rgba(var(--color-primary-rgb), 0.1);
    border-color: rgba(var(--color-primary-rgb), 0.18);
  }

  .post-card.detail:hover,
  .post-tombstone:hover {
    transform: none;
    box-shadow:
      0 1px 2px rgba(25, 28, 29, 0.04),
      0 6px 20px rgba(25, 28, 29, 0.05);
    border-color: var(--color-border);
  }

  @media (prefers-reduced-motion: reduce) {
    .post-card:hover {
      transform: none;
    }
  }

  .post-card:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .post-card.compact {
    padding: 16px;
  }

  /* Mobile: let the post body use the full card width. On desktop the whole
     content column (author line + text + media) is indented past the 48px
     avatar, which on a phone squeezes the text into a thin column that wraps
     into far more lines than needed. Rather than pull the body with fragile
     negative margins (which over/under-shot and, worse, flipped sides on
     RTL content), take the avatar OUT of the flow: absolutely position it
     top-left so the content column becomes a full-width block. The body is
     then laid out normally (no magic offset, can't crop). Only the author
     line is padded to clear the avatar. */
  @media (max-width: 768px) {
    .post-card,
    .post-card.detail,
    .post-card.compact {
      padding-inline: 12px;
    }

    .post-layout {
      display: block;
      position: relative;
    }

    .post-avatar {
      position: absolute;
      top: 0;
      /* Physical left: the avatar is always on the left in this LTR layout,
         even when the post text is RTL. */
      left: 0;
    }

    .avatar-img,
    .avatar-placeholder {
      width: 44px;
      height: 44px;
    }

    /* Clear the absolutely-positioned avatar for the header rows only; the
       body below spans the full width. 52px = avatar (44) + ~8px gap.
       The `.post-layout` prefix bumps specificity above the base
       `.post-pinned-indicator { padding-inline-start: 2px }` rule, which
       is later in the stylesheet and would otherwise win in LTR and slide
       the "Pinned" label under the avatar (clipping it to "...ed"). */
    .post-layout .post-pinned-indicator,
    .post-layout .post-author-line {
      padding-left: 52px;
      min-height: 44px;
    }
  }

  /* Main flex layout: avatar + content */
  .post-layout {
    display: flex;
    gap: 16px;
  }

  .post-avatar {
    flex-shrink: 0;
  }

  .avatar-img {
    width: 48px;
    height: 48px;
    border-radius: 9999px;
    object-fit: cover;
  }

  .compact .avatar-img {
    width: 36px;
    height: 36px;
  }

  .avatar-placeholder {
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

  .compact .avatar-placeholder {
    width: 36px;
    height: 36px;
    font-size: 0.8rem;
  }

  .post-content-col {
    flex: 1;
    min-width: 0;
  }

  /* Author line */
  .post-author-line {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: 2px;
  }

  .post-author-info {
    display: flex;
    flex-direction: column;
    gap: 0;
    min-width: 0;
  }

  .post-author-name-row {
    display: flex;
    align-items: center;
    gap: 4px;
    min-width: 0;
  }

  .post-display-name {
    font-weight: 700;
    font-size: 16px;
    color: var(--color-text);
    text-decoration: none;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .post-display-name:hover {
    text-decoration: underline;
  }

  .post-meta-row {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-top: 1px;
  }

  /* Explains an activity-ordered feed's placement, so it stays quieter
     than the handle/timestamp row above it. */
  .post-bump-row {
    display: flex;
    align-items: center;
    margin-top: 1px;
  }

  .post-bump {
    font-size: 0.75rem;
    color: var(--color-text-tertiary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .post-handle {
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
    max-width: 200px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .instance-favicon {
    width: 14px;
    height: 14px;
    border-radius: 3px;
    flex-shrink: 0;
  }

  .post-dot {
    flex-shrink: 0;
    color: var(--color-text-tertiary);
    font-size: 0.8125rem;
  }

  .post-time-link {
    color: inherit;
    text-decoration: none;
  }

  .post-time {
    white-space: nowrap;
    color: var(--color-text-secondary);
    font-size: 0.8125rem;
  }

  .post-time-link:hover .post-time {
    text-decoration: underline;
  }

  .post-edited {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .post-reply-indicator {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    margin-block-end: 4px;
  }

  .post-pinned-indicator {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-tertiary);
    margin-block-end: 4px;
    padding-inline-start: 2px;
  }

  .pinned-icon {
    font-size: 14px;
    transform: rotate(45deg);
  }

  /* "Posted in <Group>" / "Posted on <Page>" chip — sits between
     the author row and the post body so it's clear the post lives
     inside a container, not on the author's personal feed. */
  .post-scope-chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin-block-end: 8px;
    padding: 4px 10px;
    background: var(--color-primary-soft);
    color: var(--color-primary);
    border-radius: 999px;
    font-size: var(--text-xs);
    font-weight: 600;
    text-decoration: none;
    width: fit-content;
  }

  .post-scope-chip:hover {
    text-decoration: none;
    filter: brightness(1.05);
  }

  .post-scope-chip .material-symbols-outlined {
    font-size: 14px;
  }

  .post-scope-label strong {
    font-weight: 700;
  }

  .reply-icon {
    font-size: 14px;
  }

  .reply-to-link {
    color: var(--color-primary);
    text-decoration: none;
    font-weight: 500;
  }

  .reply-to-link:hover {
    text-decoration: underline;
  }

  .reply-target-media {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    color: inherit;
    font: inherit;
    cursor: pointer;
    padding: 2px 8px 2px 2px;
    border-radius: 999px;
    background: var(--color-surface-raised, var(--color-surface));
    border: 1px solid var(--color-border);
    line-height: 1;
  }

  .reply-target-media:hover:not(:disabled) {
    background: var(--color-surface-container-low, var(--color-surface-raised));
  }

  .reply-target-media:disabled {
    opacity: 0.6;
    cursor: progress;
  }

  .reply-target-thumb {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    object-fit: cover;
    flex-shrink: 0;
  }

  /* Link Card */
  .link-card {
    display: flex;
    flex-direction: column;
    border: 1px solid var(--color-border);
    border-radius: 12px;
    overflow: hidden;
    margin-block-start: 8px;
    text-decoration: none;
    color: inherit;
    transition: background 150ms ease;
  }

  .link-card:hover {
    background: var(--color-surface);
  }

  .link-card-image {
    width: 100%;
    max-height: 200px;
    overflow: hidden;
  }

  .link-card-image img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .link-card-body {
    padding: 10px 14px;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .link-card-provider {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-transform: uppercase;
    font-weight: 600;
    letter-spacing: 0.03em;
  }

  .link-card-title {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .link-card-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    line-height: 1.4;
  }

  /* Post body */
  .filter-warning {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    margin-block-start: var(--space-2);
    background: var(--color-surface-container-low);
    border-radius: var(--radius-lg);
    font-size: var(--text-sm);
    color: var(--color-on-surface-variant);
  }

  .filter-icon {
    font-size: 16px;
    color: var(--color-on-surface-variant);
  }

  .filter-text {
    flex: 1;
  }

  .filter-reveal-btn {
    background: none;
    border: none;
    color: var(--color-primary);
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-md);
    white-space: nowrap;
  }

  .filter-reveal-btn:hover {
    background: var(--color-surface-container);
  }

  .filter-hidden {
    display: none;
  }

  .post-body {
    margin-block-start: 4px;
  }

  .post-content {
    font-size: 15px;
    line-height: 1.6;
    color: var(--color-text);
    word-break: break-word;
    overflow-wrap: break-word;
    /* No `white-space: pre-line` — the markdown renderer already
       emits <p> for paragraph breaks and <br> for soft newlines, so
       preserving the literal `\n\n` between tags would just stack a
       blank visual line on top of the <p> margin and read as triple
       spacing. */
    transition: max-height 0.4s cubic-bezier(0.22, 1, 0.36, 1);
    overflow: hidden;
  }

  /* Per-paragraph auto direction so a post that mixes Arabic + English
     paragraphs (or Hebrew, Persian, Urdu, etc.) flips each block
     independently. `unicode-bidi: plaintext` tells the browser to
     apply the first-strong-character algorithm PER element, which is
     what `dir="auto"` on every paragraph would do without having to
     rewrite the sanitizer's HTML. Numbers, URLs, and LTR tokens
     inside the flipped paragraph still render left-to-right per the
     Unicode Bidirectional Algorithm — this is a visual-only change,
     not a character reversal. */
  .post-content :global(p),
  .post-content :global(li),
  .post-content :global(blockquote),
  .post-content :global(h1),
  .post-content :global(h2),
  .post-content :global(h3),
  .post-content :global(h4) {
    unicode-bidi: plaintext;
  }

  /* Custom emojis injected by renderCustomEmojis. Sized to flow with
     the surrounding text — Mastodon-style 1.2em tall, baseline-
     aligned. The trailing `vertical-align: middle` keeps tall glyphs
     (square stickers) from blowing out the line height. */
  .post-content :global(img.custom-emoji) {
    display: inline-block;
    height: 1.4em;
    width: auto;
    max-width: 100%;
    vertical-align: middle;
    margin: 0 1px;
    object-fit: contain;
  }

  /* Markdown structure styling. Posts use `white-space: pre-line`
     above to preserve single-line breaks in plain paragraphs, but
     block elements (tables, lists, headings, code blocks) need
     their own spacing so they don't collapse into adjacent text. */
  .post-content :global(h1),
  .post-content :global(h2),
  .post-content :global(h3) {
    font-weight: 700;
    line-height: 1.3;
    margin-block: 0.8em 0.4em;
  }
  .post-content :global(h1) { font-size: 1.3em; }
  .post-content :global(h2) { font-size: 1.2em; }
  .post-content :global(h3) { font-size: 1.1em; }

  .post-content :global(ul),
  .post-content :global(ol) {
    padding-inline-start: 1.5em;
    margin-block: 0.4em;
  }

  .post-content :global(blockquote) {
    border-inline-start: 3px solid var(--color-primary);
    padding-inline-start: 0.8em;
    margin-block: 0.5em;
    color: var(--color-text-secondary);
  }

  .post-content :global(code) {
    background: var(--color-surface-container-high);
    padding: 1px 5px;
    border-radius: 4px;
    font-family: var(--font-mono, monospace);
    font-size: 0.9em;
  }

  .post-content :global(pre) {
    background: var(--color-surface-container-highest);
    border: 1px solid var(--color-border);
    padding: 10px 12px;
    border-radius: 8px;
    overflow-x: auto;
    margin-block: 0.5em;
  }
  .post-content :global(pre code) {
    background: transparent;
    padding: 0;
  }

  .post-content :global(table) {
    border-collapse: collapse;
    margin-block: 0.8em;
    display: block;
    max-width: 100%;
    overflow-x: auto;
    white-space: normal;
    font-size: 0.95em;
  }
  .post-content :global(th),
  .post-content :global(td) {
    border: 1px solid var(--color-border);
    padding: 6px 10px;
    text-align: start;
    vertical-align: top;
  }
  .post-content :global(thead th) {
    background: var(--color-surface);
    font-weight: 600;
  }
  .post-content :global(tbody tr:nth-child(even)) {
    background: var(--color-surface-container-low, var(--color-surface));
  }

  .post-content :global(img) {
    max-width: 100%;
    border-radius: 8px;
    margin-block: 0.4em;
  }

  .post-content :global(hr) {
    border: 0;
    border-block-start: 1px solid var(--color-border);
    margin-block: 1em;
  }

  .post-content-collapsed {
    overflow: hidden;
  }

  .content-toggle-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    margin-block-start: 8px;
    padding: 4px 14px 4px 8px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    color: var(--color-text-secondary);
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
    transition: background 150ms ease, color 150ms ease, border-color 150ms ease;
  }

  .content-toggle-btn:hover {
    background: var(--color-primary-soft, rgba(var(--color-primary-rgb), 0.08));
    color: var(--color-primary);
    border-color: var(--color-primary);
  }

  .content-toggle-icon {
    font-size: 18px;
  }

  .content-toggle-collapse {
    margin-block-start: 12px;
  }

  /* Translate toggle — a quiet, text-first affordance under the body, styled
     to read like a link rather than compete with the action bar. */
  .translate-row {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
    margin-block-start: 8px;
  }

  .translate-btn {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 2px 4px;
    background: none;
    border: none;
    color: var(--color-primary);
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    border-radius: var(--radius-sm);
  }

  .translate-btn:hover:not(:disabled) {
    text-decoration: underline;
  }

  .translate-btn:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .translate-icon {
    font-size: 18px;
  }

  .translate-provider {
    font-size: 0.6875rem;
    color: var(--color-text-tertiary, var(--color-text-secondary));
  }

  .post-content :global(a) {
    color: var(--color-primary);
    font-weight: 500;
  }

  .post-content :global(.hashtag),
  .post-content :global(a[href*="/tags/"]) {
    color: var(--color-primary);
    font-weight: 500;
  }

  .post-content :global(p) {
    margin-block: 0 0.85em;
  }

  .post-content :global(p:last-child) {
    margin-block-end: 0;
  }

  /* Pill-style hashtag row under the body. Same visual weight as the
     `action-count` badges on the action row so the bottom of the
     post has a consistent "secondary info" tier. */
  .hashtag-footer {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-block-start: var(--space-2);
  }

  .hashtag-chip {
    display: inline-block;
    padding: 4px 10px;
    font-size: 0.8125rem;
    font-weight: 600;
    line-height: 1.2;
    color: var(--color-primary);
    background: var(--color-secondary-container);
    border-radius: 9999px;
    text-decoration: none;
    transition: background 150ms ease, color 150ms ease;
  }

  .hashtag-chip:hover {
    background: var(--color-primary);
    color: var(--color-on-primary);
    text-decoration: none;
  }

  /* CW */
  .nsfw-container {
    position: relative;
    border-radius: 8px;
    overflow: hidden;
  }

  /* When NSFW is active (not yet revealed), enforce minimum height and hide content */
  .nsfw-active:not(.nsfw-revealed) {
    min-height: 220px;
  }

  /* Content: starts fully hidden, decodes into view AFTER overlay is gone */
  .nsfw-active .nsfw-content {
    filter: blur(20px) saturate(0);
    opacity: 0;
    transform: scale(1.05);
    transition: none;
    user-select: none;
    pointer-events: none;
  }

  .nsfw-active.nsfw-revealed .nsfw-content {
    filter: blur(0) saturate(1);
    opacity: 1;
    transform: scale(1);
    user-select: auto;
    pointer-events: auto;
    transition: filter 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.35s,
                opacity 0.5s ease 0.3s,
                transform 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.35s;
  }

  /* SVG noise background */
  .nsfw-noise-svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    z-index: 0;
    pointer-events: none;
    border-radius: inherit;
    opacity: 1;
    transition: opacity 0.6s ease 0.1s;
  }

  .nsfw-revealed .nsfw-noise-svg {
    opacity: 0;
    transition: opacity 0.4s ease;
  }

  /* Touch devices: drop the NSFW frost blur, which re-blurs every scroll frame
     on mobile GPUs. The content beneath it is hidden anyway. Desktop unchanged.

     Do NOT add `content-visibility: auto` to .post-card here. It was tried
     (#71) and reverted: deferring paint until a card nears the viewport races
     the compositor, and on drivers that hand back recycled tile memory without
     zeroing it, a tile composited before its paint lands shows that stale
     memory — colored noise and smeared text over the feed. It only reproduced
     on some devices, which is why it shipped. The unbounded feed DOM it was
     papering over needs windowing in FeedList, not a paint hint. */
  @media (pointer: coarse) {
    .nsfw-frost-glass {
      backdrop-filter: none;
    }
  }

  /* Frost glass layer */
  .nsfw-frost-glass {
    position: absolute;
    inset: 0;
    z-index: 1;
    background: rgba(255, 255, 255, 0.3);
    backdrop-filter: blur(3px);
    border-radius: inherit;
    opacity: 1;
    transition: opacity 0.5s ease 0.05s;
    pointer-events: none;
  }

  .nsfw-revealed .nsfw-frost-glass {
    opacity: 0;
    transition: opacity 0.3s ease;
  }

  /* Keyed on the app theme (which resolves the OS preference for 'auto')
     rather than a bare prefers-color-scheme query, so a NSFW frost stays
     dark even when the admin forces dark on a light-OS visitor. */
  :global(:root[data-theme='dark']) .nsfw-frost-glass {
    background: rgba(0, 0, 0, 0.25);
  }

  /* Overlay with badge, warning text, and button */
  .nsfw-overlay {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 16px;
    z-index: 2;
    padding: 24px;
    text-align: center;
    opacity: 1;
    transition: opacity 0.3s ease, transform 0.4s ease;
    pointer-events: auto;
  }

  .nsfw-revealed .nsfw-overlay {
    opacity: 0;
    transform: scale(0.95);
    pointer-events: none;
  }

  .nsfw-badge {
    font-size: 0.75rem;
    font-weight: 800;
    letter-spacing: 0.05em;
    color: #fff;
    background: rgba(220, 50, 50, 0.85);
    padding: 3px 12px;
    border-radius: 6px;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
  }

  .nsfw-warning {
    font-size: 0.9375rem;
    font-weight: 700;
    color: #fff;
    line-height: 1.4;
    margin: 0;
    max-width: 300px;
    text-shadow: 0 1px 4px rgba(0, 0, 0, 0.4);
  }

  .nsfw-reveal-btn {
    margin-top: 20px;
    padding: 6px 20px;
    border: 1px solid rgba(255, 255, 255, 0.4);
    border-radius: 9999px;
    background: rgba(255, 255, 255, 0.2);
    backdrop-filter: blur(4px);
    color: #fff;
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    transition: background 150ms ease;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.2);
  }

  .nsfw-reveal-btn:hover {
    background: rgba(255, 255, 255, 0.35);
  }

  /* Hide content button — only visible when revealed */
  .nsfw-hide-btn {
    display: block;
    margin: 8px auto 4px;
    padding: 4px 14px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: var(--color-surface);
    color: var(--color-text-secondary);
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.12), 0 0 1px rgba(0, 0, 0, 0.08);
    font-size: var(--text-xs);
    font-weight: 600;
    cursor: pointer;
    position: relative;
    z-index: 3;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0s ease;
  }

  .nsfw-revealed .nsfw-hide-btn {
    opacity: 1;
    pointer-events: auto;
    transition: opacity 0.3s ease 0.5s;
  }

  .nsfw-hide-btn:hover {
    background: var(--color-surface);
  }

  /* Edit form */
  .edit-overlay {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    padding: var(--space-4);
    animation: edit-overlay-in 0.15s ease;
  }

  @keyframes edit-overlay-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .edit-dialog {
    background: var(--color-surface-container-lowest);
    border-radius: 18px;
    padding: 24px;
    max-width: 560px;
    width: 100%;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.15);
    display: flex;
    flex-direction: column;
    gap: 12px;
    animation: edit-dialog-in 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes edit-dialog-in {
    from { opacity: 0; transform: scale(0.95) translateY(4px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .edit-dialog-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .edit-dialog-title {
    font-size: 1.125rem;
    font-weight: 700;
    margin: 0;
  }

  .edit-dialog-close {
    background: transparent;
    border: none;
    color: var(--color-text-secondary);
    cursor: pointer;
    padding: 4px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .edit-dialog-close:hover {
    background: var(--color-surface-hover);
    color: var(--color-text);
  }

  .edit-dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .edit-cw-input {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 8px;
    font-size: 14px;
    font-family: inherit;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
  }

  .edit-cw-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-soft);
  }

  .edit-textarea {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 8px;
    font-size: 15px;
    font-family: inherit;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
    resize: vertical;
    line-height: 1.65;
  }

  .edit-textarea:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-soft);
  }

  .edit-error {
    font-size: 0.875rem;
    color: var(--color-danger);
  }

  /* --- Edit-mode media + toolbar --- */
  .edit-media-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
    gap: 8px;
    margin: 8px 0;
  }

  .edit-media-item {
    position: relative;
    border-radius: 10px;
    overflow: hidden;
    aspect-ratio: 1;
    background: var(--color-surface);
  }

  .edit-media-preview {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .edit-media-audio,
  .edit-media-other {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    color: var(--color-text-secondary);
    font-size: 0.875rem;
    background: var(--color-surface-container);
  }

  .edit-media-remove {
    position: absolute;
    top: 6px;
    right: 6px;
    width: 28px;
    height: 28px;
    border: 0;
    border-radius: 9999px;
    background: rgba(0, 0, 0, 0.65);
    color: #fff;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .edit-media-remove:hover {
    background: rgba(0, 0, 0, 0.85);
  }

  .edit-media-remove .material-symbols-outlined {
    font-size: 16px;
  }

  .edit-toolbar {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-block: 4px;
  }

  .edit-tool {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    height: 36px;
    min-width: 36px;
    padding: 0 10px;
    background: transparent;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    color: var(--color-text-secondary);
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
  }

  .edit-tool:hover:not(:disabled) {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .edit-tool:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .edit-tool-active {
    background: var(--color-primary-soft);
    border-color: var(--color-primary);
    color: var(--color-primary);
  }

  .edit-tool .material-symbols-outlined {
    font-size: 18px;
  }

  .edit-uploading {
    margin-inline-start: 6px;
    font-size: 0.75rem;
    color: var(--color-text-tertiary);
  }

  .edit-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .edit-cancel {
    padding: 6px 16px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: transparent;
    color: var(--color-text);
    font-size: 0.875rem;
    cursor: pointer;
  }

  .edit-cancel:hover {
    background: var(--color-surface);
  }

  .edit-save {
    padding: 6px 16px;
    border: none;
    border-radius: 9999px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    font-size: 0.875rem;
    font-weight: 700;
    cursor: pointer;
  }

  .edit-save:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .edit-save:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* Media Grid */
  .media-grid {
    display: grid;
    gap: 4px;
    margin-block-start: 12px;
    border-radius: 12px;
    overflow: hidden;
    border: var(--ghost-border);
  }

  .media-grid-1 {
    grid-template-columns: 1fr;
  }

  /* Audio-only post: kill the grid's visual frame so the
     AudioPlayer's own pill container is the only chrome. */
  .media-grid-audio-only {
    border: none;
    border-radius: 0;
    overflow: visible;
  }

  .media-grid-2 {
    grid-template-columns: 1fr 1fr;
  }

  .media-grid-4 {
    grid-template-columns: 1fr 1fr;
    grid-template-rows: auto auto;
  }

  .media-item {
    position: relative;
    overflow: hidden;
    background: var(--color-surface);
    /* Cap any feed-card media (image, video, NSFW spoiler block) at
       a fixed aspect so a tall portrait or screenshot can't blow the
       post out to multiple screens of height. The full image is
       still reachable via the lightbox / post detail. */
    aspect-ratio: 16 / 9;
    max-height: 500px;
  }

  /* Single-image / single-media posts can lean a touch taller than
     16:9 — feels right for portrait photos without producing a
     mile-long card. */
  .media-grid-1 .media-item {
    aspect-ratio: 4 / 3;
    max-height: 560px;
  }

  /* Video cells letterbox instead of cropping — clipping someone's
     subject out of frame is much worse for video than for a static
     image, where the user can click to expand. The black background
     fills the unused area inside the capped cell. */
  .media-item.media-video-cell {
    background: #000;
  }

  .media-clickable {
    cursor: zoom-in;
  }

  .media-clickable:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .media-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
    max-height: 400px;
    aspect-ratio: 16 / 9;
  }

  /* Audio attachments are pill-shaped players that want to fill
     the whole post-content column. Drop the grid cell's default
     border + padding so the player's own rounded glassmorphism
     frame is what the user sees, and force width:100% so the
     flex/grid parent doesn't shrink it to intrinsic size. */
  /* `.media-item.media-audio` (0-2-0) so it beats `.media-grid-1
     .media-item` (also 0-2-0, but earlier in source) — otherwise the
     4/3 image aspect-ratio wins and leaves a tall empty gap under the
     player. Audio sizes to its own content. */
  .media-item.media-audio {
    padding: 0;
    display: block;
    width: 100%;
    background: transparent;
    aspect-ratio: auto;
    max-height: none;
  }

  /* Poll */
  .post-poll {
    margin-block-start: 12px;
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 16px 18px;
    border: 1px solid var(--color-border);
    border-radius: 14px;
    background: var(--color-surface-raised);
  }

  /* --- Result rows: title + % above a thin track --- */
  .poll-result-row {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .poll-result-header {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
  }

  .poll-result-title {
    font-size: 0.8125rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-secondary);
    overflow-wrap: anywhere;
  }

  .poll-result-mine .poll-result-title {
    color: var(--color-text);
  }

  .poll-result-pct {
    font-size: 0.875rem;
    font-weight: 700;
    color: var(--color-text);
    font-variant-numeric: tabular-nums;
    flex-shrink: 0;
  }

  .poll-result-track {
    width: 100%;
    height: 6px;
    border-radius: 9999px;
    background: var(--color-surface-container-high, rgba(0, 0, 0, 0.08));
    overflow: hidden;
  }

  .poll-result-fill {
    height: 100%;
    background: var(--color-primary);
    border-radius: inherit;
    transition: width 350ms ease;
    /* Non-voted options sit at half-strength so the user's pick reads
       at a glance — same hue, less ink. */
    opacity: 0.4;
  }

  .poll-result-fill-mine {
    opacity: 1;
  }

  .poll-voted-check {
    color: var(--color-primary);
    font-weight: 700;
    margin-inline-end: 4px;
  }

  /* --- Vote-mode option pills (unchanged behaviour, scoped class) --- */
  .poll-option {
    position: relative;
    padding: 10px 14px;
    border-radius: 10px;
    overflow: hidden;
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.875rem;
  }

  .poll-votable {
    border: 1px solid var(--color-border);
    background: transparent;
    cursor: pointer;
    width: 100%;
    text-align: start;
    font-family: inherit;
    color: var(--color-text);
    transition: background-color 150ms ease, border-color 150ms ease;
  }

  .poll-votable:hover {
    background: var(--color-surface);
    border-color: var(--color-primary);
  }

  .poll-selected {
    border-color: var(--color-primary);
    background: var(--color-primary-soft);
  }

  .poll-check-indicator {
    flex-shrink: 0;
    font-size: 1rem;
    color: var(--color-primary);
    line-height: 1;
  }

  .poll-label {
    position: relative;
    z-index: 1;
  }

  /* Pending-vote pill: lets the user undo before the countdown
     submits. The countdown number lives inside the label so the
     button stays a single hit target. */
  .poll-cancel-btn {
    align-self: flex-start;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 14px 6px 10px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: var(--color-surface);
    color: var(--color-text);
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 150ms ease, border-color 150ms ease;
    font-variant-numeric: tabular-nums;
  }

  .poll-cancel-btn:hover {
    background: var(--color-surface-hover, var(--color-surface));
    border-color: var(--color-primary);
    color: var(--color-primary);
  }

  .poll-cancel-icon {
    font-size: 16px;
  }

  .poll-info {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .poll-voters-link {
    background: none;
    border: 0;
    padding: 0;
    color: var(--color-text-tertiary);
    font: inherit;
    cursor: pointer;
    text-decoration: underline;
    text-underline-offset: 2px;
  }

  .poll-voters-link:hover {
    color: var(--color-primary);
  }

  .voters-loading,
  .voters-empty {
    padding: 16px;
    color: var(--color-text-secondary);
    text-align: center;
  }

  .voters-list {
    list-style: none;
    margin: 0;
    padding: 4px 0;
    max-height: 60vh;
    overflow-y: auto;
  }

  .voter-row {
    margin: 0;
  }

  .voter-link {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 12px;
    color: var(--color-text);
    text-decoration: none;
    border-radius: 8px;
  }

  .voter-link:hover {
    background: var(--color-surface);
  }

  .voter-avatar {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    object-fit: cover;
    flex-shrink: 0;
  }

  .voter-name {
    font-weight: 600;
    color: var(--color-text);
  }

  .voter-handle {
    color: var(--color-text-tertiary);
    font-size: 0.875rem;
  }

  .nsfw-content {
    transition: filter 0.3s ease;
  }

  .post-actions-divider {
    height: 1px;
    background: var(--color-border);
    margin-top: 20px;
    margin-bottom: 12px;
  }
</style>

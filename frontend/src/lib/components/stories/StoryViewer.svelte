<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import {
    type StoryGroup,
    type Story,
    type StoryViewer as StoryViewerType,
    recordStoryView,
    listStoryViewers,
    reactToStory,
    unreactToStory,
    deleteStory,
  } from '$lib/api/stories.js';

  let {
    groups,
    startGroupIndex = 0,
    onclose,
    ondelete,
  }: {
    groups: StoryGroup[];
    startGroupIndex?: number;
    onclose: () => void;
    ondelete?: () => void;
  } = $props();

  // Image segments are 5s; videos use their natural duration.
  const IMAGE_DURATION_MS = 5000;

  let groupIndex = $state(startGroupIndex);
  let storyIndex = $state(0);

  let progress = $state(0); // 0..1 segment progress
  let timerId: number | null = null;
  let segmentStart = 0;
  let pausedAt: number | null = null;
  let pauseAccum = 0;
  let segmentDuration = IMAGE_DURATION_MS;

  let viewersOpen = $state(false);
  let viewers: StoryViewerType[] = $state([]);
  let viewersLoading = $state(false);

  let videoEl: HTMLVideoElement | null = $state(null);

  let currentGroup = $derived(groups[groupIndex] || null);
  let currentStory: Story | null = $derived(currentGroup?.stories[storyIndex] || null);
  let timeLeftPct = $derived(currentStory ? computeTimeLeftPct(currentStory) : 0);

  // The reaction emojis available
  const REACTIONS = ['❤️', '😂', '😮', '😢', '🔥', '👏'];

  function computeTimeLeftPct(story: Story): number {
    const total = story.duration_hours * 3600 * 1000;
    const expires = new Date(story.expires_at).getTime();
    const remaining = expires - Date.now();
    return Math.max(0, Math.min(100, (remaining / total) * 100));
  }

  function startSegment() {
    progress = 0;
    pauseAccum = 0;
    pausedAt = null;
    segmentStart = performance.now();

    if (currentStory?.media?.content_type?.startsWith('video/')) {
      // For video, progress driven by timeupdate event below; set a fallback duration
      segmentDuration = IMAGE_DURATION_MS;
    } else {
      segmentDuration = IMAGE_DURATION_MS;
      tick();
    }

    if (currentStory) {
      recordStoryView(currentStory.id).catch(() => {});
    }
  }

  function tick() {
    if (timerId !== null) cancelAnimationFrame(timerId);

    function frame() {
      if (pausedAt !== null) {
        timerId = requestAnimationFrame(frame);
        return;
      }
      const elapsed = performance.now() - segmentStart - pauseAccum;
      progress = Math.min(1, elapsed / segmentDuration);
      if (progress >= 1) {
        next();
      } else {
        timerId = requestAnimationFrame(frame);
      }
    }
    timerId = requestAnimationFrame(frame);
  }

  function pause() {
    if (pausedAt === null) {
      pausedAt = performance.now();
      videoEl?.pause();
    }
  }

  function resume() {
    if (pausedAt !== null) {
      pauseAccum += performance.now() - pausedAt;
      pausedAt = null;
      videoEl?.play().catch(() => {});
    }
  }

  function next() {
    if (!currentGroup) return;
    if (storyIndex < currentGroup.stories.length - 1) {
      storyIndex += 1;
    } else if (groupIndex < groups.length - 1) {
      groupIndex += 1;
      storyIndex = 0;
    } else {
      onclose();
      return;
    }
    startSegment();
  }

  function prev() {
    if (storyIndex > 0) {
      storyIndex -= 1;
    } else if (groupIndex > 0) {
      groupIndex -= 1;
      storyIndex = groups[groupIndex].stories.length - 1;
    } else {
      // already at first
      progress = 0;
      startSegment();
      return;
    }
    startSegment();
  }

  function handleVideoTimeupdate() {
    if (!videoEl || pausedAt !== null) return;
    if (videoEl.duration > 0) {
      progress = videoEl.currentTime / videoEl.duration;
    }
  }

  function handleVideoEnded() {
    next();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') onclose();
    else if (e.key === 'ArrowRight') next();
    else if (e.key === 'ArrowLeft') prev();
  }

  async function handleReact(emoji: string) {
    if (!currentStory) return;
    const wasSame = currentStory.user_reaction === emoji;
    try {
      if (wasSame) {
        await unreactToStory(currentStory.id);
        currentStory.user_reaction = null;
        currentStory.reaction_count = Math.max(0, currentStory.reaction_count - 1);
      } else {
        await reactToStory(currentStory.id, emoji);
        if (!currentStory.user_reaction) {
          currentStory.reaction_count += 1;
        }
        currentStory.user_reaction = emoji;
      }
    } catch {
      // ignore
    }
  }

  async function handleDelete() {
    if (!currentStory) return;
    if (!confirm('Delete this story?')) return;
    try {
      await deleteStory(currentStory.id);
      ondelete?.();
      onclose();
    } catch {
      // ignore
    }
  }

  async function openViewers() {
    if (!currentStory || !currentStory.is_own) return;
    pause();
    viewersOpen = true;
    viewersLoading = true;
    try {
      const result = await listStoryViewers(currentStory.id);
      viewers = result.viewers;
    } catch {
      viewers = [];
    } finally {
      viewersLoading = false;
    }
  }

  function closeViewers() {
    viewersOpen = false;
    viewers = [];
    resume();
  }

  function timeAgo(iso: string): string {
    const diff = Date.now() - new Date(iso).getTime();
    const min = Math.floor(diff / 60000);
    if (min < 1) return 'now';
    if (min < 60) return `${min}m`;
    const h = Math.floor(min / 60);
    if (h < 24) return `${h}h`;
    return `${Math.floor(h / 24)}d`;
  }

  $effect(() => {
    // restart segment when story changes (covers initial mount + jumps)
    void currentStory?.id;
    if (currentStory) startSegment();
  });

  onMount(() => {
    window.addEventListener('keydown', handleKeydown);
  });

  onDestroy(() => {
    if (timerId !== null) cancelAnimationFrame(timerId);
    window.removeEventListener('keydown', handleKeydown);
  });
</script>

{#if currentStory && currentGroup}
  <div
    class="story-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="Story viewer"
  >
    <div class="story-frame">
      <!-- segment bars -->
      <div class="segments">
        {#each currentGroup.stories as _, i}
          <div class="segment">
            <div
              class="segment-fill"
              style="width: {i < storyIndex ? 100 : i === storyIndex ? progress * 100 : 0}%"
            ></div>
          </div>
        {/each}
      </div>

      <!-- header -->
      <div class="header">
        <div class="author">
          {#if currentGroup.identity.avatar_url}
            <img class="author-avatar" src={currentGroup.identity.avatar_url} alt="" />
          {:else}
            <div class="author-avatar avatar-placeholder">
              {(currentGroup.identity.display_name || currentGroup.identity.handle || '?')[0].toUpperCase()}
            </div>
          {/if}
          <div class="author-meta">
            <div class="author-name">{currentGroup.identity.display_name || currentGroup.identity.handle}</div>
            <div class="author-time">{timeAgo(currentStory.published_at)}</div>
          </div>
        </div>
        <div class="header-actions">
          {#if currentStory.is_own}
            <button type="button" class="icon-btn" onclick={handleDelete} aria-label="Delete story">
              <span class="material-symbols-outlined">delete</span>
            </button>
          {/if}
          <button type="button" class="icon-btn" onclick={onclose} aria-label="Close">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>
      </div>

      <!-- media -->
      <div
        class="media"
        onpointerdown={pause}
        onpointerup={resume}
        onpointercancel={resume}
        onpointerleave={resume}
        role="presentation"
      >
        {#if currentStory.media}
          {#if currentStory.media.content_type.startsWith('video/')}
            <video
              bind:this={videoEl}
              src={currentStory.media.url}
              autoplay
              playsinline
              ontimeupdate={handleVideoTimeupdate}
              onended={handleVideoEnded}
            ></video>
          {:else}
            <img src={currentStory.media.url} alt={currentStory.caption || ''} />
          {/if}
        {/if}

        {#if currentStory.caption}
          <div class="caption">{currentStory.caption}</div>
        {/if}

        <!-- nav zones (must not block pointer events on media) -->
        <button class="nav-zone left" type="button" onclick={prev} aria-label="Previous"></button>
        <button class="nav-zone right" type="button" onclick={next} aria-label="Next"></button>
      </div>

      <!-- footer: reactions or viewer count -->
      <div class="footer">
        {#if currentStory.is_own}
          <button type="button" class="viewer-count" onclick={openViewers}>
            <span class="material-symbols-outlined">visibility</span>
            {currentStory.view_count} {currentStory.view_count === 1 ? 'viewer' : 'viewers'}
          </button>
        {:else}
          <div class="reactions">
            {#each REACTIONS as emoji}
              <button
                type="button"
                class="reaction-btn"
                class:active={currentStory.user_reaction === emoji}
                onclick={() => handleReact(emoji)}
                aria-label={`React with ${emoji}`}
              >
                {emoji}
              </button>
            {/each}
          </div>
        {/if}
      </div>

      <!-- 2px decay bar at the very bottom -->
      <div class="time-decay" aria-hidden="true">
        <div class="time-decay-fill" style="width: {timeLeftPct}%"></div>
      </div>
    </div>
  </div>

  {#if viewersOpen}
    <div class="viewers-overlay" role="dialog" aria-modal="true">
      <div class="viewers-sheet">
        <div class="viewers-header">
          <div>Viewers ({viewers.length})</div>
          <button type="button" class="icon-btn" onclick={closeViewers} aria-label="Close viewers">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>
        <div class="viewers-list">
          {#if viewersLoading}
            <div class="viewers-empty">Loading…</div>
          {:else if viewers.length === 0}
            <div class="viewers-empty">No viewers yet</div>
          {:else}
            {#each viewers as v}
              <div class="viewer-row">
                {#if v.account.avatar_url}
                  <img class="viewer-avatar" src={v.account.avatar_url} alt="" />
                {:else}
                  <div class="viewer-avatar avatar-placeholder">
                    {(v.account.display_name || v.account.handle || '?')[0].toUpperCase()}
                  </div>
                {/if}
                <div class="viewer-meta">
                  <div class="viewer-name">{v.account.display_name || v.account.acct || v.account.handle}</div>
                  <div class="viewer-handle">@{v.account.acct || v.account.handle}</div>
                </div>
                <div class="viewer-time">{timeAgo(v.viewed_at)}</div>
              </div>
            {/each}
          {/if}
        </div>
      </div>
    </div>
  {/if}
{/if}

<style>
  .story-overlay {
    position: fixed;
    inset: 0;
    background: var(--scrim-strong);
    z-index: 1000;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 16px;
  }

  .story-frame {
    position: relative;
    width: 100%;
    /* Scale the frame off the viewport height so wide desktop windows
       don't waste 60% of the screen on letterboxing. The clamp keeps
       a sensible portrait shape (~9:16 derives from `90vh * 0.5625`)
       while capping at 560 px so a 4K display doesn't render an
       absurdly large card. The previous 420 px ceiling left huge
       black bars on anything wider than a phone. */
    max-width: clamp(320px, calc(90vh * 0.5625), 560px);
    max-width: clamp(320px, calc(90dvh * 0.5625), 560px);
    height: 100%;
    max-height: 90vh;
    max-height: 90dvh;
    background: #000;
    border-radius: 14px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .segments {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    display: flex;
    gap: 4px;
    padding: 8px;
    z-index: 3;
  }

  .segment {
    flex: 1;
    height: 3px;
    background: rgba(255, 255, 255, 0.3);
    border-radius: 2px;
    overflow: hidden;
  }

  .segment-fill {
    height: 100%;
    background: white;
    transition: width 80ms linear;
  }

  .header {
    position: absolute;
    top: 18px;
    left: 0;
    right: 0;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 12px;
    z-index: 3;
  }

  .author {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .author-avatar {
    width: 32px;
    height: 32px;
    border-radius: 50%;
    object-fit: cover;
    border: 1.5px solid white;
  }

  .avatar-placeholder {
    background: var(--color-primary);
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
  }

  .author-name {
    color: white;
    font-size: 0.875rem;
    font-weight: 600;
    text-shadow: 0 1px 4px rgba(0,0,0,0.6);
  }

  .author-time {
    color: rgba(255, 255, 255, 0.8);
    font-size: 0.72rem;
  }

  .header-actions {
    display: flex;
    gap: 4px;
  }

  .icon-btn {
    background: transparent;
    border: none;
    color: white;
    cursor: pointer;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .icon-btn:hover {
    background: rgba(255, 255, 255, 0.15);
  }

  .icon-btn .material-symbols-outlined {
    font-size: 22px;
  }

  .media {
    flex: 1;
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    background: #000;
  }

  .media img,
  .media video {
    max-width: 100%;
    max-height: 100%;
    width: 100%;
    height: 100%;
    object-fit: contain;
  }

  .caption {
    position: absolute;
    left: 16px;
    right: 16px;
    bottom: 80px;
    color: white;
    font-size: 1rem;
    text-align: center;
    text-shadow: 0 2px 6px rgba(0,0,0,0.8);
    padding: 8px 12px;
    background: var(--scrim-medium);
    border-radius: 10px;
    backdrop-filter: blur(4px);
    z-index: 2;
  }

  .nav-zone {
    position: absolute;
    top: 0;
    bottom: 0;
    width: 35%;
    background: transparent;
    border: none;
    cursor: pointer;
    z-index: 1;
  }

  .nav-zone.left { left: 0; }
  .nav-zone.right { right: 0; }

  .footer {
    position: absolute;
    bottom: 14px;
    left: 0;
    right: 0;
    padding: 0 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 3;
  }

  .reactions {
    display: flex;
    gap: 6px;
    background: var(--scrim-medium);
    padding: 6px 10px;
    border-radius: 999px;
    backdrop-filter: blur(8px);
  }

  .reaction-btn {
    background: transparent;
    border: none;
    font-size: 1.4rem;
    cursor: pointer;
    transition: transform 150ms ease;
    padding: 4px;
    line-height: 1;
  }

  .reaction-btn:hover {
    transform: scale(1.25);
  }

  .reaction-btn.active {
    transform: scale(1.3);
    filter: drop-shadow(0 0 6px rgba(255,200,80,0.8));
  }

  .viewer-count {
    background: var(--scrim-medium);
    color: white;
    border: none;
    padding: 8px 16px;
    border-radius: 999px;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 0.875rem;
    backdrop-filter: blur(8px);
  }

  .viewer-count .material-symbols-outlined {
    font-size: 18px;
  }

  .time-decay {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 2px;
    background: rgba(255,255,255,0.15);
    z-index: 4;
  }

  .time-decay-fill {
    height: 100%;
    background: linear-gradient(90deg, #ee2a7b, #f9a826);
    transition: width 60s linear;
  }

  /* Viewers sheet */
  .viewers-overlay {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    z-index: 1100;
    display: flex;
    align-items: flex-end;
    justify-content: center;
  }

  .viewers-sheet {
    width: 100%;
    /* Mirror .story-frame's responsive cap so the sheet aligns with
       the frame above it when desktop sizing kicks in. */
    max-width: clamp(320px, calc(90vh * 0.5625), 560px);
    max-width: clamp(320px, calc(90dvh * 0.5625), 560px);
    background: var(--color-surface);
    border-radius: 16px 16px 0 0;
    max-height: 70vh;
    max-height: 70dvh;
    display: flex;
    flex-direction: column;
  }

  .viewers-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 16px;
    border-bottom: 1px solid var(--color-border);
    font-weight: 600;
    color: var(--color-text);
  }

  .viewers-header .icon-btn { color: var(--color-text); }
  .viewers-header .icon-btn:hover { background: var(--color-surface-container); }

  .viewers-list {
    overflow-y: auto;
    padding: 8px 0;
  }

  .viewers-empty {
    text-align: center;
    padding: 32px;
    color: var(--color-text-secondary);
  }

  .viewer-row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 16px;
  }

  .viewer-avatar {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    object-fit: cover;
  }

  .viewer-meta {
    flex: 1;
    min-width: 0;
  }

  .viewer-name {
    font-weight: 600;
    color: var(--color-text);
    font-size: 0.875rem;
  }

  .viewer-handle {
    color: var(--color-text-secondary);
    font-size: 0.75rem;
  }

  .viewer-time {
    color: var(--color-text-secondary);
    font-size: 0.75rem;
  }
</style>

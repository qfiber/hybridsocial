<script lang="ts">
  import { t } from '$lib/stores/i18n.js';
  import { onMount } from 'svelte';
  import { listStoryFeed, type StoryGroup, type StoryMedia } from '$lib/api/stories.js';
  import { currentUser } from '$lib/stores/auth.js';
  import StoryViewer from './StoryViewer.svelte';
  import StoryComposer from './StoryComposer.svelte';

  let groups: StoryGroup[] = $state([]);
  let loading = $state(true);
  let viewerOpen = $state(false);
  let viewerStartIndex = $state(0);
  let composerOpen = $state(false);

  let me = $derived($currentUser);

  let selfGroup = $derived(groups.find((g) => g.is_self) || null);
  let otherGroups = $derived(groups.filter((g) => !g.is_self));

  async function load() {
    try {
      const result = await listStoryFeed();
      groups = result.groups;
    } catch {
      groups = [];
    } finally {
      loading = false;
    }
  }

  function openViewer(authorId: string) {
    const idx = groups.findIndex((g) => g.identity.id === authorId);
    if (idx >= 0) {
      viewerStartIndex = idx;
      viewerOpen = true;
    }
  }

  function handleSelfTileClick() {
    if (selfGroup && selfGroup.stories.length > 0) {
      openViewer(selfGroup.identity.id);
    } else {
      composerOpen = true;
    }
  }

  function openComposer() {
    composerOpen = true;
  }

  function handleStoryCreated() {
    composerOpen = false;
    load();
  }

  function handleStoryDeleted() {
    load();
  }

  onMount(() => {
    load();

    function refresh() { load(); }
    window.addEventListener('story-created', refresh);
    window.addEventListener('story-deleted', refresh);
    return () => {
      window.removeEventListener('story-created', refresh);
      window.removeEventListener('story-deleted', refresh);
    };
  });
</script>

{#if !loading && (selfGroup || otherGroups.length > 0 || me)}
  <div class="stories-carousel" aria-label={$t('stories.label')}>
    <div class="stories-track">
      {#if me}
        <!-- Self / "Create story" tile. Two-pane Facebook-style layout:
             top 70% shows the user's avatar (or first own-story preview
             when one exists), bottom 30% is a label band with a "+"
             chip straddling the seam. Clicking the tile composes a
             new story; clicking the body when own stories exist
             opens the viewer instead. -->
        <div class="story-tile self-tile">
          <button
            type="button"
            class="tile-button"
            onclick={handleSelfTileClick}
            aria-label={selfGroup ? 'View your story' : 'Add to your story'}
          >
            <div class="self-cover">
              {@render coverMedia(
                selfGroup && selfGroup.stories[0]?.media
                  ? selfGroup.stories[0].media
                  : null,
                me.avatar_url,
                me.display_name || me.handle || '?'
              )}
            </div>
            <div class="self-footer">
              <span class="self-label">{$t('stories.create')}</span>
            </div>
            <span
              class="self-plus"
              role="presentation"
              aria-hidden="true"
            >
              <span class="material-symbols-outlined">add</span>
            </span>
          </button>
          <!-- Stops the parent button so the explicit "Add" affordance
               always opens the composer even when the user already has
               a story (where tile-button defaults to viewing). -->
          <button
            type="button"
            class="self-plus-target"
            onclick={(e) => { e.stopPropagation(); openComposer(); }}
            aria-label={$t('stories.add')}
          ></button>
        </div>
      {/if}

      {#each otherGroups as group (group.identity.id)}
        {@const cover = group.stories[0]?.media ?? null}
        {@const name = group.identity.display_name || group.identity.handle}
        <div class="story-tile">
          <button
            type="button"
            class="tile-button"
            onclick={() => openViewer(group.identity.id)}
            aria-label={`View ${name}'s story`}
          >
            <div class="tile-cover">
              {@render coverMedia(cover, null, name)}
              <div class="tile-shade" aria-hidden="true"></div>
            </div>
            <span
              class="tile-avatar"
              class:tile-avatar-unviewed={!group.all_viewed}
              aria-hidden="true"
            >
              {#if group.identity.avatar_url}
                <img src={group.identity.avatar_url} alt="" />
              {:else}
                <span class="tile-avatar-placeholder">
                  {(name || '?')[0].toUpperCase()}
                </span>
              {/if}
            </span>
            <span class="tile-name">{name}</span>
          </button>
        </div>
      {/each}
    </div>
  </div>
{/if}

{#snippet coverMedia(media: StoryMedia | null, fallbackAvatarUrl: string | null | undefined, fallbackInitial: string)}
  {#if media && media.content_type.startsWith('image/')}
    <img class="cover-img" src={media.url} alt="" loading="lazy" decoding="async" />
  {:else if media && media.content_type.startsWith('video/')}
    <!-- preload=metadata is enough to render the first frame as the
         poster. The carousel never plays so we don't need the body. -->
    <video
      class="cover-img"
      src={media.url}
      preload="metadata"
      muted
      playsinline
      aria-hidden="true"
    ></video>
  {:else if fallbackAvatarUrl}
    <img class="cover-img cover-img-avatar" src={fallbackAvatarUrl} alt="" loading="lazy" />
  {:else}
    <span class="cover-fallback">{fallbackInitial[0]?.toUpperCase()}</span>
  {/if}
{/snippet}

{#if viewerOpen}
  <StoryViewer
    {groups}
    startGroupIndex={viewerStartIndex}
    onclose={() => { viewerOpen = false; load(); }}
    ondelete={handleStoryDeleted}
  />
{/if}

{#if composerOpen}
  <StoryComposer onclose={() => composerOpen = false} oncreated={handleStoryCreated} />
{/if}

<style>
  .stories-carousel {
    width: 100%;
    /* No outer card chrome — the tiles themselves are the visual
       chrome (Facebook-style) and a wrapping panel just steals
       horizontal space on narrow viewports. */
    padding: 4px 0 8px;
  }

  .stories-track {
    display: flex;
    gap: 8px;
    overflow-x: auto;
    scrollbar-width: none;
    padding: 4px 2px;
    /* Snap each tile to its leading edge so flick-scrolling lands
       neatly instead of mid-tile. */
    scroll-snap-type: x mandatory;
  }

  .stories-track::-webkit-scrollbar { display: none; }

  .story-tile {
    position: relative;
    flex: 0 0 auto;
    width: 112px;
    /* 9:16 portrait story tiles. */
    aspect-ratio: 9 / 16;
    border-radius: 14px;
    overflow: hidden;
    background: var(--color-surface-container, var(--color-surface));
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06);
    scroll-snap-align: start;
    transition: transform 200ms ease, box-shadow 200ms ease;
  }

  .story-tile:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.12);
  }

  .tile-button {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    background: transparent;
    border: none;
    padding: 0;
    cursor: pointer;
    color: inherit;
    display: block;
    text-align: start;
  }

  /* --- Friend / other-user tile --- */

  .tile-cover {
    position: absolute;
    inset: 0;
    overflow: hidden;
  }

  .tile-cover :global(.cover-img),
  .self-cover :global(.cover-img) {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .tile-cover :global(.cover-fallback),
  .self-cover :global(.cover-fallback) {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-primary-hover, var(--color-primary)) 100%);
    color: var(--color-on-primary);
    font-size: 2rem;
    font-weight: 700;
  }

  /* Bottom gradient so the white name stays legible no matter what
     the underlying photo looks like. */
  .tile-shade {
    position: absolute;
    inset: 0;
    background: linear-gradient(180deg, rgba(0, 0, 0, 0) 50%, rgba(0, 0, 0, 0.55) 100%);
    pointer-events: none;
  }

  .tile-avatar {
    position: absolute;
    top: 8px;
    inset-inline-start: 8px;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    overflow: hidden;
    background: var(--color-surface);
    /* Default = "viewed": a subtle white outline keeps the avatar
       readable against any photo without screaming "new content". */
    box-shadow: 0 0 0 2px var(--color-surface), 0 0 0 3px rgba(0, 0, 0, 0.2);
  }

  /* "Unviewed" = blue ring like Facebook. We use the brand primary
     so it inherits whatever theme palette the instance picks. */
  .tile-avatar-unviewed {
    box-shadow: 0 0 0 2px var(--color-surface), 0 0 0 4px var(--color-primary);
  }

  .tile-avatar img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .tile-avatar-placeholder {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary);
    color: var(--color-on-primary);
    font-size: 0.95rem;
    font-weight: 700;
  }

  .tile-name {
    position: absolute;
    inset-inline: 8px;
    bottom: 8px;
    color: #fff;
    font-size: 0.78rem;
    font-weight: 600;
    line-height: 1.15;
    /* Two-line clamp keeps long display names from overrunning the
       tile while still showing more context than a single ellipsis. */
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    text-shadow: 0 1px 3px rgba(0, 0, 0, 0.55);
  }

  /* --- Self / "Create story" tile --- */

  .self-tile .tile-button {
    display: flex;
    flex-direction: column;
  }

  .self-cover {
    position: relative;
    flex: 0 0 70%;
    overflow: hidden;
    background: var(--color-surface-container, var(--color-surface));
  }

  /* When the cover is the user's avatar (no story posted yet) crop a
     bit tighter and add a subtle wash so the "+" chip below has a
     clean canvas. */
  .self-cover :global(.cover-img-avatar) {
    object-position: center 30%;
  }

  .self-footer {
    flex: 1 1 auto;
    background: var(--color-surface-raised, var(--color-surface));
    display: flex;
    align-items: flex-end;
    justify-content: center;
    padding: 6px 8px 10px;
  }

  .self-label {
    font-size: 0.78rem;
    font-weight: 600;
    color: var(--color-text);
    text-align: center;
    line-height: 1.2;
  }

  /* The blue "+" chip straddles the seam between the cover and the
     footer, exactly like Facebook. Pointer-events disabled so the
     dedicated `.self-plus-target` button below catches the click. */
  .self-plus {
    position: absolute;
    left: 50%;
    top: 70%;
    transform: translate(-50%, -50%);
    width: 30px;
    height: 30px;
    border-radius: 50%;
    background: var(--color-primary);
    color: var(--color-on-primary);
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 0 0 3px var(--color-surface-raised, var(--color-surface));
    pointer-events: none;
  }

  .self-plus .material-symbols-outlined {
    font-size: 20px;
    font-weight: 700;
  }

  /* Invisible button laid over the +-chip so users tapping the
     bottom area always go straight to the composer, even when the
     user already has a story (where the main tile-button defaults
     to "view"). 56-px tall hit area covers the seam comfortably. */
  .self-plus-target {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 56px;
    background: transparent;
    border: none;
    padding: 0;
    cursor: pointer;
  }

  /* Phones: shrink tiles a touch so 4 fit comfortably across a
     360-pixel viewport (4 × 92 + 3 × 8 = 392 — fits with the
     standard mobile padding). */
  @media (max-width: 480px) {
    .story-tile {
      width: 96px;
      border-radius: 12px;
    }
    .tile-avatar {
      width: 32px;
      height: 32px;
    }
    .self-plus {
      width: 28px;
      height: 28px;
    }
  }
</style>

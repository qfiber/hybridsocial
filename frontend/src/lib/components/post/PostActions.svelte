<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import { api } from '$lib/api/client.js';
  import { authStore } from '$lib/stores/auth.js';
  import { mute, unmute, block, unblock, blockDomain } from '$lib/api/accounts.js';
  import { pinPost, unpinPost } from '$lib/api/statuses.js';
  import { get } from 'svelte/store';
  import { on } from 'svelte/events';
  import ReactionPicker from './ReactionPicker.svelte';
  import RadialReactionPicker from './RadialReactionPicker.svelte';
  import ShareToGroupModal from './ShareToGroupModal.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { markSeen } from '$lib/utils/seen-posts.js';
  import { t } from '$lib/stores/i18n.js';
  // Plain translate for imperative use (toasts / config objects).
  import { t as translate } from '$lib/utils/i18n.js';

  let {
    post,
    onedit,
    oncomment,
    viewerContext = null,
  }: {
    post: Post;
    onedit?: () => void;
    // When provided, the reply/comment button calls this instead of opening
    // the global composer. Streams uses it to open an in-place comments sheet
    // (view + reply) rather than only launching a reply composer. Other call
    // sites omit it and keep the default composer behaviour.
    oncomment?: () => void;
    // Matches PostCard.viewerContext. Used so the pin menu entry
    // disappears when the post's pin lives in a scope different from
    // the feed the user is looking at — i.e. don't offer "Unpin" from
    // the profile feed when the pin actually belongs to a group.
    viewerContext?: 'profile' | 'group' | 'page' | null;
  } = $props();

  // What scope this post's pin lives in. Falls back to the
  // implicit scope inferred from group_id / page_id presence for
  // older backends that don't yet ship `pin_scope`.
  let pinScope = $derived<'profile' | 'group' | 'page'>(
    (post.pin_scope as 'profile' | 'group' | 'page' | null | undefined) ??
      (post.group ? 'group' : post.page ? 'page' : 'profile'),
  );

  // Canonical 7 default reactions — must match ReactionPicker.svelte
  // exactly so a click on 👍 doesn't display as 😀 elsewhere on the
  // card (the stacked summary chip, the user's "current reaction"
  // mark, the floating-emoji animation on tap, and the Reactions
  // detail modal all read from this map).
  const reactionEmojis: Record<string, string> = {
    like: '\u{1F44D}', // 👍
    love: '\u{2764}\u{FE0F}', // ❤️
    wow: '\u{1F92F}', // 🤯
    care: '\u{1F970}', // 🥰
    angry: '\u{1F621}', // 😡
    sad: '\u{1F622}', // 😢
    lol: '\u{1F602}', // 😂
  };

  import { onMount } from 'svelte';
  import { premiumCatalog, ensurePremiumCatalog, type PremiumReactionGlyph } from '$lib/stores/reaction-catalog.js';
  import { openMenuId } from '$lib/stores/open-menu.js';
  import { currentUser } from '$lib/stores/auth.js';

  // Premium reactions are admin-curated bare shortcodes like "fire".
  // Without resolving them through the shared catalog they used to
  // render as their literal text inside every reaction site (stack,
  // current-reaction mark, floating animation, reactions modal).
  ensurePremiumCatalog();
  function premiumGlyph(type: string): PremiumReactionGlyph | undefined {
    return $premiumCatalog.get(type);
  }

  let isBoosted = $state(post.is_boosted);
  let boostCount = $state(post.boost_count);
  let replyCount = $state(post.reply_count);
  let reactionCount = $state(post.reaction_count);
  // Local mirror of the server flag — mutating `post.is_bookmarked`
  // directly was unreliable because `post` is a $props() proxy and
  // doesn't always propagate back to the parent's reactivity graph,
  // so the menu icon never updated and it looked like the click
  // had failed even though the server stored the bookmark.
  let isBookmarked = $state(!!post.is_bookmarked);
  let currentReaction = $state(post.current_user_reaction);
  let showReactionPicker = $state(false);

  // ── Touch dial state ─────────────────────────────────────────────
  // Long-press on the like button opens a radial picker (see
  // RadialReactionPicker.svelte). The desktop hover-grid above is
  // untouched — those handlers fire on real mouseenter, not on touch.
  let radialOpen = $state(false);
  let radialOriginX = $state(0);
  let radialOriginY = $state(0);
  let radialTouchX = $state(0);
  let radialTouchY = $state(0);
  let radialHighlighted = $state<string | null>(null);
  let longPressTimer: ReturnType<typeof setTimeout> | null = null;
  // Track the starting touch point so we can cancel the long-press
  // when the user starts scrolling instead of holding.
  let touchStartX = 0;
  let touchStartY = 0;
  // Set to true once the dial is committed (or cancelled) so the
  // synthetic click that follows touchend doesn't fall through to
  // toggleReactionPicker() and double-fire as a stray "like".
  let touchHandled = false;
  let touchHandledTimer: ReturnType<typeof setTimeout> | null = null;
  // Set when a second finger joins: the gesture is no longer a tap or a
  // dial drag, and must not commit a reaction when the fingers lift.
  let touchGestureVoid = false;
  // True once a long-press has opened the dial and the finger lifted
  // without picking: the dial stays open, waiting for a tap. Lets the
  // window-click dismiss handler ignore the very release that armed it.
  let radialArmedForTap = $state(false);
  // Wall-clock timestamp (ms epoch) up to which any pointerenter /
  // mouseenter on the wrapper is treated as a touch-synthesized event
  // and ignored. Without this, Android Chrome fires a phantom
  // mouseenter after touchend → the desktop picker would pop up
  // *behind* the radial dial — see Screenshot_20260519_215337.
  let suppressHoverUntil = 0;
  const LONG_PRESS_MS = 320;
  const SCROLL_CANCEL_PX = 12;
  // How far outside the button a finger may lift and still count as a
  // tap. Mirrors native click tolerance; independent of SCROLL_CANCEL_PX,
  // which only decides whether the long-press is still armed.
  const TAP_SLOP_PX = 12;

  // Below-vs-above flip: the picker normally renders above the like
  // button, but on a post near the top of the viewport that sends
  // the picker off the top of the screen. Measure the trigger rect
  // when the picker opens and flip below if there isn't enough room
  // above to fit the 2-row picker.
  let reactionTriggerEl: HTMLButtonElement | undefined = $state();
  let reactionPickerBelow = $state(false);
  const REACTION_PICKER_ESTIMATED_HEIGHT = 130;

  $effect(() => {
    if (!showReactionPicker || !reactionTriggerEl) return;
    const rect = reactionTriggerEl.getBoundingClientRect();
    const spaceAbove = rect.top;
    const spaceBelow = window.innerHeight - rect.bottom;
    // Prefer above (existing behavior). Only flip if above is too
    // tight AND below has more room — keeps the popover stable when
    // both sides are roomy.
    reactionPickerBelow =
      spaceAbove < REACTION_PICKER_ESTIMATED_HEIGHT && spaceBelow > spaceAbove;
  });
  let showMoreMenu = $state(false);
  let bounceReaction = $state(false);
  let floatingEmoji = $state<string | null>(null);
  let showReactionDetail = $state(false);
  let reactionDetailData = $state<{type: string; count: number; accounts: {id: string; handle: string; acct?: string; display_name: string | null; avatar_url: string | null}[]}[]>([]);
  let reactionDetailLoading = $state(false);
  let reactionDetailTab = $state('all');
  let reactions = $state(post.reactions || []);
  // Seed from the server-provided flag so admins who already muted
  // a thread see "Unmute notifications" on first render, not the
  // stale "Mute notifications" that assumes every post is un-muted.
  let isPostMuted = $state(!!post.is_muted);

  onMount(() => {
    function handleReplyCount(e: Event) {
      const { postId, delta } = (e as CustomEvent).detail;
      if (postId === post.id) {
        replyCount = Math.max(0, replyCount + delta);
      }
    }

    // Keyboard-shortcut bridge: the global handler dispatches an
    // action against the focused post id; we route it to the same
    // function the click would call so behavior (toasts, optimistic
    // counters, tier limits) stays identical.
    function handleShortcutAction(e: Event) {
      const detail = (e as CustomEvent<{ id: string; action: string }>).detail;
      if (!detail || detail.id !== post.id) return;
      const synthetic = new MouseEvent('click');
      switch (detail.action) {
        case 'reply':
          handleReply(synthetic);
          break;
        case 'boost':
          handleBoost(synthetic);
          break;
        case 'react':
          // `f` mirrors Mastodon's favourite — leave a 👍 by default.
          handleReaction('like');
          break;
      }
    }

    window.addEventListener('reply-count-update', handleReplyCount);
    window.addEventListener('post-shortcut-action', handleShortcutAction);
    return () => {
      window.removeEventListener('reply-count-update', handleReplyCount);
      window.removeEventListener('post-shortcut-action', handleShortcutAction);
    };
  });

  let isOwnPost = $derived(() => {
    const state = get(authStore);
    return state.user?.id === post.account.id;
  });

  let isRemotePost = $derived(() => {
    const acct = post.account.acct || post.account.handle;
    return acct.includes('@');
  });

  // The source domain of a remote post's author (user@host → host), used by
  // the "Block domain" action so a viewer can shut out a whole instance —
  // most useful for unwanted federated video in Streams.
  let postDomain = $derived(() => {
    const acct = post.account.acct || post.account.handle;
    return acct.includes('@') ? acct.split('@')[1] || '' : '';
  });

  // "Display on original instance" only makes sense for federated
  // posts. For those, the origin permalink is `post.uri` (the AP
  // object id, which every major server — Mastodon, Pleroma, Misskey
  // — serves as HTML under browser content negotiation). `post.url`
  // is always built from our own endpoint in the serializer, so
  // using it here would open the local copy and the menu item would
  // be misleading. For local posts (which don't show this menu item
  // anyway), fall back to `url` so the value is non-empty.
  let remotePostUrl = $derived(
    isRemotePost() ? (post.uri || post.url || '') : (post.url || '')
  );

  // Confirmation dialog state
  let confirmAction: 'mute_user' | 'unmute_user' | 'block_user' | 'unblock_user' | null = $state(null);

  // $derived so the copy re-resolves when the locale changes.
  let confirmMessages = $derived<Record<string, { title: string; message: string; button: string }>>({
    mute_user: { title: $t('post.mute_user_title'), message: $t('post.mute_user_msg'), button: $t('profile.mute') },
    unmute_user: { title: $t('post.unmute_user_title'), message: $t('post.unmute_user_msg'), button: $t('profile.unmute') },
    block_user: { title: $t('post.block_user_title'), message: $t('post.block_user_msg'), button: $t('profile.block') },
    unblock_user: { title: $t('post.unblock_user_title'), message: $t('post.unblock_user_msg'), button: $t('profile.unblock') },
  });

  // Report modal state
  let showReportModal = $state(false);
  let reportCategory = $state('spam');
  let reportDescription = $state('');
  let reportSubmitting = $state(false);
  let reportError = $state('');
  let reportStep = $state<1 | 2>(1);
  let reportBlock = $state(false);
  let reportForward = $state(false);

  // Whether the reported account lives on another instance.
  // acct contains "@host" for remote; local accts are bare.
  let reportIsRemote = $derived(
    !!(post.account as any)?.acct && (post.account as any).acct.includes('@')
  );
  let reportRemoteDomain = $derived(
    reportIsRemote ? ((post.account as any).acct.split('@')[1] || '') : ''
  );

  // Values are the enum sent to the backend — keep them; translate labels.
  let reportCategories = $derived([
    { value: 'spam', label: $t('report.spam') },
    { value: 'harassment', label: $t('report.harassment') },
    { value: 'hate_speech', label: $t('report.hate_speech') },
    { value: 'illegal', label: $t('report.illegal') },
    { value: 'misinformation', label: $t('report.misinformation') },
    { value: 'other', label: $t('report.other') },
  ]);

  async function handleReply(e: MouseEvent) {
    e.stopPropagation();
    if (oncomment) {
      oncomment();
      return;
    }
    window.dispatchEvent(new CustomEvent('open-composer', { detail: { replyTo: post } }));
  }

  async function handleBoost(e: MouseEvent) {
    e.stopPropagation();
    try {
      if (isBoosted) {
        await api.delete(`/api/v1/statuses/${post.id}/boost`);
        isBoosted = false;
        boostCount = Math.max(0, boostCount - 1);
      } else {
        await api.post(`/api/v1/statuses/${post.id}/boost`);
        isBoosted = true;
        boostCount += 1;
      }
    } catch {
      // Revert on error
    }
  }

  async function handleReaction(emoji: string) {
    showReactionPicker = false;
    try {
      if (currentReaction === emoji) {
        await api.delete(`/api/v1/statuses/${post.id}/react`);
        markSeen(post.id);
        // Remove from reactions array
        reactions = reactions
          .map(r => r.name === emoji ? { ...r, count: r.count - 1, me: false } : r)
          .filter(r => r.count > 0);
        currentReaction = null;
        reactionCount = Math.max(0, reactionCount - 1);
      } else {
        const previousReaction = currentReaction;
        const hadReaction = previousReaction !== null;
        await api.post(`/api/v1/statuses/${post.id}/react`, { type: emoji });
        markSeen(post.id);
        currentReaction = emoji;
        if (!hadReaction) reactionCount += 1;

        // Remove old reaction from array if switching
        if (hadReaction && previousReaction !== emoji) {
          reactions = reactions.map(r => r.name === previousReaction ? { ...r, count: r.count - 1, me: false } : r).filter(r => r.count > 0);
        }

        // Add/increment new reaction (only if not already counted as mine)
        const existing = reactions.find(r => r.name === emoji);
        if (existing) {
          if (!existing.me) {
            reactions = reactions.map(r => r.name === emoji ? { ...r, count: r.count + 1, me: true } : r);
          }
        } else {
          reactions = [...reactions, { name: emoji, count: 1, me: true }];
        }
        // Trigger floating emoji animation
        floatingEmoji = emoji;
        setTimeout(() => { floatingEmoji = null; }, 800);
      }
      bounceReaction = true;
      setTimeout(() => { bounceReaction = false; }, 400);
    } catch {
      // Revert on error
    }
  }

  let hoverTimer: ReturnType<typeof setTimeout> | null = null;

  // Shared by the click path (mouse, keyboard) and the touchend path.
  function applyTapReaction() {
    // If already reacted, tapping removes the reaction.
    if (currentReaction) {
      handleReaction(currentReaction);
      return;
    }
    // Default tap leaves a 👍 (like). The picker is still reachable
    // via hover on desktop and via long-press on touch.
    showReactionPicker = false;
    showMoreMenu = false;
    showReactionDetail = false;
    handleReaction('like');
  }

  function toggleReactionPicker(e: MouseEvent) {
    e.stopPropagation();
    // A touch sequence already handled this interaction — most UAs
    // won't synthesize a click at all now that we cancel touchstart,
    // but Firefox on Windows does. Guard against a double reaction.
    if (touchHandled) {
      touchHandled = false;
      return;
    }
    applyTapReaction();
  }

  // The default 7 reactions every user can pick. Mirrors the canonical
  // list in ReactionPicker.svelte / reactionEmojis above — keep all
  // three in sync.
  let defaultRadialReactions = $derived<Array<{ type: string; emoji: string; label: string; image?: string | null }>>([
    { type: 'like', emoji: '\u{1F44D}', label: $t('reaction.like') },
    { type: 'love', emoji: '\u{2764}\u{FE0F}', label: $t('reaction.love') },
    { type: 'wow', emoji: '\u{1F92F}', label: $t('reaction.wow') },
    { type: 'care', emoji: '\u{1F970}', label: $t('reaction.care') },
    { type: 'angry', emoji: '\u{1F621}', label: $t('reaction.angry') },
    { type: 'sad', emoji: '\u{1F622}', label: $t('reaction.sad') },
    { type: 'lol', emoji: '\u{1F602}', label: $t('reaction.lol') },
  ]);

  // Premium reactions get appended for tiers whose limits include
  // `custom_emoji` — same gate the desktop ReactionPicker uses. The
  // radial layout adapts its radius to the count, so this can grow
  // up to a sensible cap without crowding the arc.
  const RADIAL_MAX = 14;
  let isPremiumUser = $derived(!!$currentUser?.limits?.custom_emoji);
  let radialReactions = $derived.by(() => {
    if (!isPremiumUser) return defaultRadialReactions;
    const extras: Array<{ type: string; emoji: string; label: string; image?: string | null }> = [];
    for (const [type, glyph] of $premiumCatalog) {
      extras.push({
        type,
        emoji: glyph.character || ':' + type + ':',
        label: type,
        image: glyph.image_url ?? null,
      });
    }
    return [...defaultRadialReactions, ...extras].slice(0, RADIAL_MAX);
  });

  // Suppress the one click a nonconformant UA may still synthesize
  // after a touch sequence (Firefox on Windows). Re-arm rather than
  // stack, so a second tap inside the window isn't left unguarded when
  // the first tap's timer expires.
  function armClickGuard() {
    touchHandled = true;
    if (touchHandledTimer) clearTimeout(touchHandledTimer);
    touchHandledTimer = setTimeout(() => {
      touchHandled = false;
      touchHandledTimer = null;
    }, 400);
  }

  function cancelLongPress() {
    if (longPressTimer) {
      clearTimeout(longPressTimer);
      longPressTimer = null;
    }
  }

  function reactionTouchStart(e: TouchEvent) {
    if (e.touches.length !== 1) {
      // A second finger landed. Abandon the whole gesture: pinch-zoom
      // and two-finger taps must not leave a reaction behind.
      touchGestureVoid = true;
      cancelLongPress();
      radialOpen = false;
      radialHighlighted = null;
      return;
    }
    touchGestureVoid = false;
    radialArmedForTap = false;
    // Suppress the native long-press menu (Copy / Share / Select all
    // on Android; the iOS callout). Without this, the OS hijacks the
    // gesture mid-hold and pops a text-selection toolbar over the
    // post — see Screenshot_20260519_215315 / _215337.
    if (e.cancelable) e.preventDefault();
    // Touch input takes the desktop hover-picker offline for this
    // interaction; suppressTouchUntil also blocks the synthetic
    // mouseenter that mobile browsers emit after touch.
    suppressHoverUntil = Date.now() + 800;
    if (showReactionPicker) showReactionPicker = false;
    if (hoverTimer) {
      clearTimeout(hoverTimer);
      hoverTimer = null;
    }
    const t = e.touches[0];
    touchStartX = t.clientX;
    touchStartY = t.clientY;
    touchHandled = false;
    // Center the dial on the like button, not on the finger — keeps
    // the arc symmetric regardless of where the user pressed.
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    radialOriginX = rect.left + rect.width / 2;
    radialOriginY = rect.top + rect.height / 2;
    radialTouchX = t.clientX;
    radialTouchY = t.clientY;
    if (longPressTimer) clearTimeout(longPressTimer);
    longPressTimer = setTimeout(() => {
      longPressTimer = null;
      // If the OS started a selection before we cancelled the gesture,
      // drop it — otherwise iOS's selection loupe steals the touch and
      // the browser fires touchcancel, closing the dial mid-drag. Never
      // touch a selection the user is holding inside a field: in Chrome
      // removeAllRanges() clears a focused textarea's selection too.
      const active = document.activeElement;
      const editing =
        active instanceof HTMLInputElement ||
        active instanceof HTMLTextAreaElement ||
        (active instanceof HTMLElement && active.isContentEditable);
      if (!editing) {
        window.getSelection()?.removeAllRanges();
      }
      radialOpen = true;
      // Claim the shared single-popover slot so any menu or tray open on
      // another post closes immediately (and ours closes if another claims
      // it — see the effect above).
      openMenuId.set(trayTag);
      // Belt and suspenders — if the desktop picker somehow opened
      // (e.g. a stray mouseenter slipped through before suppressHover
      // armed), close it so the two pickers never stack.
      showReactionPicker = false;
      // Subtle haptic so the user knows the dial has armed.
      if (typeof navigator !== 'undefined' && navigator.vibrate) {
        navigator.vibrate(12);
      }
    }, LONG_PRESS_MS);
  }

  function reactionTouchMove(e: TouchEvent) {
    if (e.touches.length !== 1) return;
    const t = e.touches[0];
    radialTouchX = t.clientX;
    radialTouchY = t.clientY;

    // If the user has clearly started scrolling before the long-press
    // fires, abort the long-press so the page can scroll normally.
    if (longPressTimer) {
      const dx = t.clientX - touchStartX;
      const dy = t.clientY - touchStartY;
      if (Math.hypot(dx, dy) > SCROLL_CANCEL_PX) {
        clearTimeout(longPressTimer);
        longPressTimer = null;
      }
    } else if (radialOpen) {
      // Stop the browser from also treating the move as a scroll —
      // once the dial is open, the gesture belongs to us.
      if (e.cancelable) e.preventDefault();
    }
  }

  function reactionTouchEnd(e: TouchEvent) {
    const wasRadial = radialOpen;
    cancelLongPress();
    // Keep blocking synthesized mouseenter for a moment past touchend
    // — Android Chrome fires it ~300ms after the last touch lifts.
    suppressHoverUntil = Date.now() + 800;

    // Because touchstart is now cancelled for real, the browser will
    // not synthesize mousedown/mouseup/click for this gesture (Touch
    // Events L2 §"Mouse event dispatch"). The tap path can no longer
    // ride on `onclick` — it has to be driven from here. `touchHandled`
    // stays as a guard for the UAs that fire the click anyway.
    if (e.cancelable) e.preventDefault();
    armClickGuard();

    // Fingers still down, or a second one joined earlier: this was
    // never a tap and never a dial commit. Bail without reacting.
    if (touchGestureVoid || e.touches.length > 0) {
      radialOpen = false;
      radialHighlighted = null;
      return;
    }

    if (wasRadial) {
      const picked = radialHighlighted;
      if (picked) {
        // Drag-and-release: commit immediately and close.
        radialOpen = false;
        radialHighlighted = null;
        handleReaction(picked);
      } else {
        // Released without aiming at an emoji (a plain long-press, or the
        // finger drifted back to the dead zone). Keep the dial open so
        // the user can now *tap* an emoji — the second half of the
        // "drag OR tap" model. Dismissed by the next outside tap.
        radialArmedForTap = true;
      }
    } else {
      // Short tap. Reproduce native click semantics — the browser fires
      // a click when the finger lifts over the element it started on,
      // however much it wobbled in between — rather than measuring
      // travel from the start point, which would lose the taps of large
      // thumbs and shaky hands. A deliberate drag away still cancels,
      // since touchend targets the origin element wherever the finger
      // ended up. Screen readers may send touchend with no coordinates
      // at all; treat that as a tap on the button.
      const t = e.changedTouches[0];
      const x = t?.clientX ?? touchStartX;
      const y = t?.clientY ?? touchStartY;
      const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
      const releasedOnButton =
        x >= r.left - TAP_SLOP_PX && x <= r.right + TAP_SLOP_PX &&
        y >= r.top - TAP_SLOP_PX && y <= r.bottom + TAP_SLOP_PX;
      if (releasedOnButton) {
        applyTapReaction();
      }
    }

  }

  function handleRadialPick(type: string) {
    radialOpen = false;
    radialHighlighted = null;
    radialArmedForTap = false;
    // Tapping a tray cell dispatches pointer/mouse events that the
    // browser follows with a synthesized `click` at the finger point.
    // Because the tray overlay is pointer-events:none except on the
    // cells, that click would fall through to whatever post/button sits
    // behind the tray (the "second click" seen on device). Swallow the
    // next click once, in the capture phase, before it reaches anything.
    swallowNextClick();
    handleReaction(type);
  }

  let clickSwallower: ((e: MouseEvent) => void) | null = null;
  function swallowNextClick() {
    if (typeof window === 'undefined') return;
    if (clickSwallower) window.removeEventListener('click', clickSwallower, true);
    clickSwallower = (e: MouseEvent) => {
      e.stopPropagation();
      e.preventDefault();
      window.removeEventListener('click', clickSwallower!, true);
      clickSwallower = null;
    };
    window.addEventListener('click', clickSwallower, true);
    setTimeout(() => {
      if (clickSwallower) {
        window.removeEventListener('click', clickSwallower, true);
        clickSwallower = null;
      }
    }, 700);
  }

  function reactionTouchCancel() {
    cancelLongPress();
    suppressHoverUntil = Date.now() + 800;
    // The gesture was taken away from us; no click that follows is one
    // the user meant as a tap.
    armClickGuard();
    radialOpen = false;
    radialHighlighted = null;
  }

  // Svelte 5 hardcodes `{ passive: true }` for `touchstart` and
  // `touchmove` (PASSIVE_EVENTS in svelte/src/utils.js) on both the
  // delegated and the direct listener path, so the `preventDefault()`
  // calls in reactionTouchStart / reactionTouchMove are silently
  // discarded. The OS long-press gesture is then never suppressed:
  // iOS Safari starts a text selection over the post, claims the touch
  // and fires `touchcancel`, which closes the dial mid-gesture.
  // Bind these two by hand so they are non-passive. `touchend` and
  // `touchcancel` are not in PASSIVE_EVENTS and stay as attributes.
  function nonPassiveTouch(node: HTMLElement) {
    const options: AddEventListenerOptions = { passive: false };
    const offStart = on(node, 'touchstart', reactionTouchStart, options);
    const offMove = on(node, 'touchmove', reactionTouchMove, options);
    return {
      destroy() {
        offStart();
        offMove();
      },
    };
  }

  let closeTimer: ReturnType<typeof setTimeout> | null = null;

  function handleReactionHoverOut() {
    if (hoverTimer) {
      clearTimeout(hoverTimer);
      hoverTimer = null;
    }
    if (showReactionPicker) {
      closeTimer = setTimeout(() => {
        showReactionPicker = false;
      }, 100);
    }
  }

  function handleReactionHoverIn(e?: PointerEvent) {
    // Hard guard against touch input: filter the actual PointerEvent
    // by pointerType, and back-stop with a time window after the last
    // touchstart in case the browser dispatches a bare mouseenter.
    if (e && e.pointerType !== 'mouse') return;
    if (Date.now() < suppressHoverUntil) return;
    if (radialOpen) return;
    // Cancel close timer if re-entering
    if (closeTimer) {
      clearTimeout(closeTimer);
      closeTimer = null;
    }
    // Don't open picker if detail popover is showing
    if (showReactionPicker || showReactionDetail) return;
    hoverTimer = setTimeout(() => {
      showReactionPicker = true;
      showMoreMenu = false;
    }, 200);
  }

  let menuOpenUpward = $state(false);
  // Cap the menu so it never extends past the visible content area
  // — the bottom tab bar on mobile (64px) was clipping the lower
  // items (Mute/Block/Report) since the menu uses --z-dropdown (10)
  // which sits below --z-sticky (20). Set as inline style when we
  // toggle so the cap reflects the actual trigger position.
  let menuMaxHeight = $state<string>('');

  // A unique tag per PostActions instance so the global `openMenuId`
  // store can identify which menu is currently expanded across the
  // whole feed. Without this, opening a second post's ⋯ menu left
  // the first one stacked on screen — see the screenshot in PR review.
  const instanceId = Math.random().toString(36).slice(2, 8);
  const menuTag = `post-actions:${post.id}:${instanceId}`;
  const trayTag = `reaction-tray:${post.id}:${instanceId}`;

  // Close the menu the moment another instance becomes the active
  // one, or when something clears the store (window click outside,
  // Escape press handled in the listener below).
  $effect(() => {
    const active = $openMenuId;
    if (showMoreMenu && active !== menuTag) {
      showMoreMenu = false;
    }
  });

  // Inverse: when we close (by any path — menu item click, toggle off,
  // etc.) and we still own the global slot, release it so a window
  // click later doesn't fire a no-op against a stale tag, and so
  // other instances don't see us as "still active".
  $effect(() => {
    if (showMoreMenu) return;
    if (get(openMenuId) === menuTag) openMenuId.set(null);
  });

  function closeRadial() {
    radialOpen = false;
    radialHighlighted = null;
    radialArmedForTap = false;
  }

  // Backdrop tap dismiss: closing the tray flips the overlay back to
  // pointer-events:none synchronously, so the click that this tap will
  // synthesize would land on the element behind. Swallow that click.
  function dismissTrayFromBackdrop() {
    closeRadial();
    swallowNextClick();
  }

  // Same single-popover coordination for the reaction tray: close it the
  // moment any other menu or tray becomes the active popover, and release
  // the slot when the tray closes by any path. Ensures two posts can't
  // both show a tray at once.
  $effect(() => {
    const active = $openMenuId;
    if (radialOpen && active !== trayTag) {
      closeRadial();
    }
  });
  $effect(() => {
    if (radialOpen) return;
    if (get(openMenuId) === trayTag) openMenuId.set(null);
  });

  // The tray is positioned from the button's viewport rect captured at
  // press time. Once the page scrolls (or rotates) that rect is stale, so
  // a genuine scroll dismisses it. But opening the tray can itself nudge
  // the scroll position (a short post whose tray extends past the
  // viewport, or iOS rubber-banding), and that incidental scroll must NOT
  // close the tray we just opened — that was the "first tap does nothing"
  // symptom. So ignore scrolls for a short grace period after opening, and
  // only dismiss on a scroll that actually moves the page.
  $effect(() => {
    if (!radialOpen || typeof window === 'undefined') return;
    const openedAt = Date.now();
    const startScrollY = window.scrollY;
    const onScroll = () => {
      if (Date.now() - openedAt < 350) return;
      if (Math.abs(window.scrollY - startScrollY) < 4) return;
      closeRadial();
    };
    const onResize = () => closeRadial();
    window.addEventListener('scroll', onScroll, { capture: true, passive: true });
    window.addEventListener('resize', onResize, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll, { capture: true });
      window.removeEventListener('resize', onResize);
    };
  });

  // One window-level click + escape listener per instance is fine —
  // they cheaply dismiss the global store and every other instance
  // closes via the effect above. Only mount the listeners while the
  // menu is open so an idle feed doesn't have N listeners running.
  $effect(() => {
    if (!showMoreMenu) return;
    function onDocClick(e: MouseEvent) {
      const t = e.target as Node | null;
      // Click inside the menu or its trigger? Leave it open.
      if (t && menuRootEl && menuRootEl.contains(t)) return;
      openMenuId.set(null);
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') openMenuId.set(null);
    }
    // `true` (capture) so we win against PostCard's own click handler,
    // which would otherwise consume the event before we see it.
    document.addEventListener('click', onDocClick, true);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('click', onDocClick, true);
      document.removeEventListener('keydown', onKey);
    };
  });

  let menuRootEl: HTMLDivElement | undefined = $state();

  function toggleMoreMenu(e: MouseEvent) {
    e.stopPropagation();
    showReactionPicker = false;

    if (showMoreMenu) {
      // Already ours — toggle off.
      openMenuId.set(null);
      showMoreMenu = false;
      return;
    }

    // Check if the button is near the bottom of the viewport.
    // On mobile (<=768px) the BottomTabs bar takes the bottom 64px,
    // so subtract that from the downward budget — otherwise we'd
    // happily open downward into the tab bar and clip the lower menu
    // items behind it.
    const btn = e.currentTarget as HTMLElement;
    const rect = btn.getBoundingClientRect();
    const isMobile = window.matchMedia('(max-width: 768px)').matches;
    const bottomReserved = isMobile ? 64 : 0;
    const headerReserved = 64;
    const padding = 12;
    const spaceBelow = window.innerHeight - rect.bottom - bottomReserved - padding;
    const spaceAbove = rect.top - headerReserved - padding;
    // Open upward when there's notably more room above. Either way,
    // bound the menu height to whatever space we actually have so
    // long lists scroll inside the menu instead of overflowing.
    menuOpenUpward = spaceAbove > spaceBelow && spaceAbove > 200;
    const available = Math.max(160, menuOpenUpward ? spaceAbove : spaceBelow);
    menuMaxHeight = `${Math.min(available, 360)}px`;

    // Claim the global slot — every other PostActions instance sees
    // the change via $openMenuId and closes its own menu.
    openMenuId.set(menuTag);
    showMoreMenu = true;
  }

  // The post's video attachment, if any — gates the "Download video" item
  // (present on Streams clips and any video post).
  let postVideo = $derived(post.media_attachments?.find((m) => m.type === 'video'));

  async function handleDownloadVideo(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    const url = postVideo?.url || (postVideo as any)?.remote_url;
    if (!url) return;
    const name = `stream-${post.id}.mp4`;
    try {
      // Fetch → blob so the browser saves the file even for a cross-origin
      // (federated) URL, where an <a download> would just navigate.
      const res = await fetch(url);
      if (!res.ok) throw new Error('bad response');
      const blob = await res.blob();
      const obj = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = obj;
      a.download = name;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(obj);
    } catch {
      // CORS / network error → open in a new tab so the viewer can still save it.
      window.open(url, '_blank', 'noopener');
    }
  }

  async function handleShare(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;

    const url = `${window.location.origin}/post/${post.id}`;
    const title = translate('post.share_title', { name: post.account.display_name || post.account.handle });
    const text = (post.content || '').slice(0, 200);

    // Only invoke the native share sheet on touch devices, where it's the
    // expected UX. On desktop navigator.share exists too (e.g. Brave) but opens
    // the browser's own share menu, which isn't what people want from a post's
    // Share — so there we copy the link straight to the clipboard instead.
    const coarsePointer =
      typeof window.matchMedia === 'function' && window.matchMedia('(pointer: coarse)').matches;

    if (coarsePointer && navigator.share) {
      try {
        await navigator.share({ title, text, url });
        return;
      } catch {
        // User cancelled or share failed — fall through to copy
      }
    }

    // Desktop (or no native share): copy the link and confirm.
    try {
      await navigator.clipboard.writeText(url);
      window.dispatchEvent(new CustomEvent('toast', { detail: { message: translate('post.link_copied'), type: 'success' } }));
    } catch {
      window.dispatchEvent(new CustomEvent('toast', { detail: { message: translate('post.link_copy_failed'), type: 'error' } }));
    }
  }

  async function handleBookmark(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    const wasBookmarked = isBookmarked;
    // Optimistic flip on the LOCAL state so the menu icon updates
    // immediately and reactively. Roll back on failure.
    isBookmarked = !wasBookmarked;
    try {
      if (wasBookmarked) {
        await api.delete(`/api/v1/statuses/${post.id}/bookmark`);
        // Pages that show bookmark-only feeds (e.g. /bookmarks)
        // listen for this event and animate the row out, matching
        // the post-deleted dissolve. Other consumers ignore it.
        window.dispatchEvent(
          new CustomEvent('bookmark-removed', { detail: { id: post.id } }),
        );
        window.dispatchEvent(
          new CustomEvent('toast', { detail: { message: translate('post.bookmark_removed'), type: 'success' } }),
        );
      } else {
        await api.post(`/api/v1/statuses/${post.id}/bookmark`);
        window.dispatchEvent(
          new CustomEvent('toast', { detail: { message: translate('post.bookmark_saved'), type: 'success' } }),
        );
      }
    } catch {
      isBookmarked = wasBookmarked;
      window.dispatchEvent(
        new CustomEvent('toast', { detail: { message: translate('post.bookmark_failed'), type: 'error' } }),
      );
    }
  }

  function handleEdit(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    onedit?.();
  }

  let isPinned = $state(!!post.is_pinned);

  async function handlePinToggle(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    const wasPinned = isPinned;
    try {
      const updated = wasPinned ? await unpinPost(post.id) : await pinPost(post.id);
      isPinned = !!updated.is_pinned;
      // Notify the profile page so it can reorder pinned posts to the top.
      window.dispatchEvent(
        new CustomEvent('post-pin-changed', {
          detail: { id: post.id, pinned: isPinned, post: updated },
        }),
      );
      // Pin scope is whichever container the post lives in: a
      // group anchor makes it a group pin, a page anchor a page pin,
      // otherwise it's a profile pin. Match the toast wording so a
      // group admin pinning someone else's post in their group sees
      // "Pinned in group" rather than the confusing "Pinned to
      // profile".
      const scope = post.group ? 'group' : post.page ? 'page' : 'profile';
      const message = translate(`post.${isPinned ? 'pinned' : 'unpinned'}_${scope}`);
      window.dispatchEvent(
        new CustomEvent('toast', {
          detail: { message, type: 'success' },
        }),
      );
    } catch (err: unknown) {
      // The pin endpoint returns 422 with `{error: "limits.max_pinned_posts", max, scope}`
      // when the user is over their pin allowance for that scope.
      // Surface the limit so they know to unpin something first /
      // upgrade.
      const apiErr = err as {
        body?: { error?: string; max?: number; scope?: string };
        message?: string;
      };
      let message = translate('post.pin_failed');
      if (apiErr?.body?.error === 'limits.max_pinned_posts') {
        const max = apiErr.body.max ?? 1;
        const scope = apiErr.body.scope ?? 'profile';
        const noun = translate(`post.pin_noun_${scope === 'group' || scope === 'page' ? scope : 'profile'}`);
        message = translate('post.pin_limit', { noun, max });
      } else if (apiErr?.body?.error === 'status.forbidden') {
        message = translate('post.pin_no_permission');
      }
      window.dispatchEvent(
        new CustomEvent('toast', { detail: { message, type: 'error' } }),
      );
    }
  }

  function handleReport(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    reportCategory = 'spam';
    reportDescription = '';
    reportError = '';
    reportStep = 1;
    reportBlock = false;
    // For remote accounts default forwarding ON — the origin
    // instance is in the best position to act on it.
    reportForward = reportIsRemote;
    showReportModal = true;
  }

  function reportNext() {
    reportError = '';
    reportStep = 2;
  }

  function reportBack() {
    reportStep = 1;
  }

  async function submitReport() {
    reportSubmitting = true;
    reportError = '';
    try {
      await api.post('/api/v1/reports', {
        reported_id: post.account.id,
        target_type: 'post',
        target_id: post.id,
        category: reportCategory,
        description: reportDescription,
        block_account: reportBlock,
        forward: reportIsRemote && reportForward,
      });
      showReportModal = false;
    } catch {
      reportError = translate('report.submit_failed');
    } finally {
      reportSubmitting = false;
    }
  }

  function cancelReport() {
    showReportModal = false;
  }

  function handleQuote(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    window.dispatchEvent(new CustomEvent('open-composer', { detail: { quotePost: post } }));
  }

  // Edit history
  let showHistoryModal = $state(false);
  let historyData = $state<{id: string; content: string; content_html: string; edited_at: string; revision_number: number}[]>([]);
  let historyLoading = $state(false);

  async function handleViewHistory(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    showHistoryModal = true;
    historyLoading = true;
    try {
      historyData = await api.get(`/api/v1/statuses/${post.id}/history`);
    } catch { /* */ }
    finally { historyLoading = false; }
  }

  function handleDisplayOnInstance(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    if (remotePostUrl) {
      window.open(remotePostUrl, '_blank', 'noopener,noreferrer');
    }
  }

  function handleMuteNotifications(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    togglePostMute();
  }

  async function togglePostMute() {
    try {
      if (isPostMuted) {
        await api.delete(`/api/v1/statuses/${post.id}/mute`);
        isPostMuted = false;
      } else {
        await api.post(`/api/v1/statuses/${post.id}/mute`);
        isPostMuted = true;
      }
    } catch { /* handle error */ }
  }

  function handleMentionUser(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    const mention = post.account.acct || post.account.handle;
    window.dispatchEvent(new CustomEvent('open-composer', { detail: { prefill: `@${mention} ` } }));
  }

  function handleChatWithUser(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    // Route to /messages/new with the recipient pre-filled. The
    // new-conversation page reads `?to=` on mount, resolves the
    // handle, and either starts a conversation or falls through to
    // a direct post (for peers that don't speak DMs) — the same flow
    // users get via the "Message" button on a profile page.
    const handle = post.account.acct || post.account.handle;
    window.location.href = `/messages/new?to=${encodeURIComponent(handle)}`;
  }

  function handleMuteUser(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    confirmAction = 'mute_user';
  }

  function handleBlockUser(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    confirmAction = 'block_user';
  }

  async function executeConfirmedAction() {
    if (!confirmAction) return;
    try {
      switch (confirmAction) {
        case 'mute_user':
          await mute(post.account.id);
          dismissClip();
          break;
        case 'unmute_user':
          await unmute(post.account.id);
          break;
        case 'block_user':
          await block(post.account.id);
          dismissClip();
          break;
        case 'unblock_user':
          await unblock(post.account.id);
          break;
      }
    } catch { /* handle error */ }
    confirmAction = null;
  }

  // Remove this clip from the feed it lives in right now. Feeds listen for
  // `post-deleted` and drop the matching row (same convention as delete), so
  // the offending clip vanishes immediately; the server-side block/mute/domain
  // filter keeps the rest of that source out of the next page.
  function dismissClip() {
    window.dispatchEvent(new CustomEvent('post-deleted', { detail: { id: post.id } }));
  }

  // "Not interested" — hide just this clip locally, no server call. The durable,
  // reviewable controls are Block account / Block domain (Settings → Blocked & muted).
  function handleNotInterested(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    dismissClip();
    addToast(translate('block.hidden'), 'info');
  }

  async function handleBlockDomain(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    const domain = postDomain();
    if (!domain) return;
    try {
      await blockDomain(domain);
      dismissClip();
      addToast(translate('block.domain_blocked', { domain }), 'success');
    } catch {
      addToast(translate('block.domain_error'), 'error');
    }
  }

  // Share-to-group: picks from the groups the viewer has joined, then hands off
  // to the composer (quote + group scope). A first-class menu entry rather than
  // a hidden composer option.
  let showShareToGroup = $state(false);
  function handleShareToGroup(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    showShareToGroup = true;
  }

  let showDeleteConfirm = $state(false);

  function handleDelete(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    showDeleteConfirm = true;
  }

  async function confirmDelete() {
    try {
      await api.delete(`/api/v1/statuses/${post.id}`);
      window.dispatchEvent(new CustomEvent('post-deleted', { detail: { id: post.id } }));
    } catch {
      // Handle error
    }
    showDeleteConfirm = false;
  }

  function cancelDelete() {
    showDeleteConfirm = false;
  }

  function handleActionKeydown(e: KeyboardEvent, action: () => void) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      e.stopPropagation();
      action();
    }
  }

  async function fetchReactionDetail() {
    if (reactionDetailLoading) return;
    showReactionDetail = !showReactionDetail;
    showReactionPicker = false;
    showMoreMenu = false;
    reactionDetailTab = 'all';
    if (!showReactionDetail) return;
    reactionDetailLoading = true;
    try {
      reactionDetailData = await api.get(`/api/v1/statuses/${post.id}/reactions`);
    } catch { /* */ }
    finally { reactionDetailLoading = false; }
  }

  // Close menus on outside click
  function handleWindowClick() {
    showReactionPicker = false;
    showMoreMenu = false;
    showReactionDetail = false;
  }

  // Dismiss an open, tap-armed tray on the next pointerdown outside it.
  // Using pointerdown (not click) lets us swallow the click that this
  // same tap will synthesize, so dismissing the tray doesn't also
  // activate whatever sits behind it (a post, link, or button). Taps on
  // an emoji cell call handleRadialPick + stopPropagation, so they never
  // reach here.
  function handleWindowPointerDown(e: PointerEvent) {
    if (!radialArmedForTap && !radialOpen) return;
    const target = e.target as HTMLElement | null;
    // A tap inside the tray itself is handled by the cell (or is dead
    // space); don't treat it as an outside-dismiss.
    if (target && target.closest && target.closest('.tray-overlay')) return;
    radialArmedForTap = false;
    radialOpen = false;
    radialHighlighted = null;
    // Eat the click this pointerdown will produce so it can't fall
    // through onto the element behind the tray.
    swallowNextClick();
  }
</script>

<svelte:window onclick={handleWindowClick} onpointerdown={handleWindowPointerDown} />

{#snippet reactionGlyph(type: string, sizeClass: string)}
  {#if reactionEmojis[type]}
    <span class={sizeClass}>{reactionEmojis[type]}</span>
  {:else}
    {@const g = premiumGlyph(type)}
    {#if g?.image_url}
      <img class="{sizeClass} reaction-glyph-img" src={g.image_url} alt={type} />
    {:else if g?.character}
      <span class={sizeClass}>{g.character}</span>
    {:else}
      <span class={sizeClass}>{type}</span>
    {/if}
  {/if}
{/snippet}

<div class="post-actions" role="group" aria-label={$t('post.actions_label')}>
  <div class="post-actions-left">
    <!-- Like / React -->
    <div
      class="action-reaction-wrapper"
      onpointerenter={handleReactionHoverIn}
      onpointerleave={(e) => { if (e.pointerType === 'mouse') handleReactionHoverOut(); }}
    >
      <button
        type="button"
        class="action-btn action-like"
        class:active-reaction={currentReaction !== null}
        class:bounce={bounceReaction}
        bind:this={reactionTriggerEl}
        onclick={toggleReactionPicker}
        use:nonPassiveTouch
        ontouchend={reactionTouchEnd}
        ontouchcancel={reactionTouchCancel}
        oncontextmenu={(e) => e.preventDefault()}
        aria-label={$t('post.react_aria')}
        aria-expanded={showReactionPicker}
      >
        {#if currentReaction}
          {#if currentReaction.startsWith(':') && currentReaction.endsWith(':')}
            <img class="current-reaction-custom" src="/api/v1/custom_emojis/{currentReaction.slice(1, -1)}/image" alt={currentReaction} />
          {:else}
            {@render reactionGlyph(currentReaction, 'current-reaction')}
          {/if}
        {:else}
          <svg
            class="action-icon"
            viewBox="0 0 24 24"
            width="1em"
            height="1em"
            fill="none"
            stroke="currentColor"
            stroke-width="1.8"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M8.35 17.5H5.5C4.94772 17.5 4.5 17.0523 4.5 16.5V11.5C4.5 10.9477 4.94772 10.5 5.5 10.5H8.35C8.43284 10.5 8.5 10.5672 8.5 10.65V17.35C8.5 17.4328 8.43284 17.5 8.35 17.5Z" />
            <path d="M8.5 11.5L10.3944 7.71115C10.4639 7.57229 10.5 7.41918 10.5 7.26393V5.5C10.5 4.94772 10.9477 4.5 11.5 4.5C12.6046 4.5 13.5 5.39543 13.5 6.5V10.5" />
            <path d="M11.5 10.5H17.4972C18.1637 10.5 18.6437 11.1397 18.4573 11.7796L16.7098 17.7796C16.5855 18.2065 16.1943 18.5 15.7497 18.5H11.9142C11.649 18.5 11.3946 18.3946 11.2071 18.2071L10.7929 17.7929C10.6054 17.6054 10.351 17.5 10.0858 17.5H8.5" />
          </svg>
        {/if}
        {#if reactionCount > 0}
          <span class="action-count">{reactionCount}</span>
        {/if}
        {#if floatingEmoji}
          {@render reactionGlyph(floatingEmoji, 'floating-emoji')}
        {/if}
      </button>

      {#if showReactionPicker}
        <div class="picker-anchor" class:picker-anchor-below={reactionPickerBelow}>
          <ReactionPicker
            selected={currentReaction}
            onselect={handleReaction}
          />
        </div>
      {/if}
    </div>

    {#if radialOpen}
      <RadialReactionPicker
        originX={radialOriginX}
        originY={radialOriginY}
        touchX={radialTouchX}
        touchY={radialTouchY}
        reactions={radialReactions}
        bind:highlightedType={radialHighlighted}
        onpick={handleRadialPick}
        armed={radialArmedForTap}
        ondismiss={dismissTrayFromBackdrop}
      />
    {/if}

    <!-- Comment -->
    {#if post.replies_locked_at}
      <button
        type="button"
        class="action-btn action-reply action-reply-locked"
        disabled
        aria-label={$t('post.replies_disabled_aria')}
        title={$t('post.replies_disabled_aria')}
      >
        <span class="material-symbols-outlined action-icon">speaker_notes_off</span>
        <span class="action-locked-label">{$t('post.replies_disabled')}</span>
      </button>
    {:else}
      <button
        type="button"
        class="action-btn action-reply"
        onclick={handleReply}
        onkeydown={(e) => handleActionKeydown(e, () => handleReply(new MouseEvent('click')))}
        aria-label={$t('post.reply_aria', { count: replyCount })}
      >
        <svg
          class="action-icon"
          class:filled={replyCount > 0}
          viewBox="0 0 24 24"
          width="1em"
          height="1em"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M8 10.5H16M8 14.5H11M21.0039 12C21.0039 16.9706 16.9745 21 12.0039 21C9.9675 21 3.00463 21 3.00463 21C3.00463 21 4.56382 17.2561 3.93982 16.0008C3.34076 14.7956 3.00391 13.4372 3.00391 12C3.00391 7.02944 7.03334 3 12.0039 3C16.9745 3 21.0039 7.02944 21.0039 12Z" />
        </svg>
        {#if replyCount > 0}
          <span class="action-count">{replyCount}</span>
        {/if}
      </button>
    {/if}

    <!-- Share / Boost -->
    <button
      type="button"
      class="action-btn action-boost"
      class:active-boost={isBoosted}
      onclick={handleBoost}
      aria-label="{isBoosted ? $t('post.undo_boost') : $t('post.boost')} ({boostCount})"
      aria-pressed={isBoosted}
    >
      <span class="material-symbols-outlined action-icon">cached</span>
      {#if boostCount > 0}
        <span class="action-count">{boostCount}</span>
      {/if}
    </button>
  </div>

  <div class="post-actions-right">
    <!-- Top reactions used by others (clickable for detail) -->
    {#if reactionCount > 0}
      {@const sorted = reactions.filter(r => r.count > 0).sort((a, b) => b.count - a.count)}
      <button
        type="button"
        class="reaction-stack"
        onclick={(e) => { e.stopPropagation(); fetchReactionDetail(); }}
        aria-label={$t('post.view_reactions')}
      >
        <span class="reaction-stack-emojis">
          {#each sorted.slice(0, 3) as r, i (r.name)}
            <span class="reaction-stack-emoji" style="z-index: {3 - i}">
              {@render reactionGlyph(r.name, 'reaction-stack-glyph')}
            </span>
          {/each}
        </span>
      </button>
    {/if}

    <!-- Options (3 dots) -->
    <div class="action-more-wrapper" bind:this={menuRootEl}>
    <button
      type="button"
      class="action-btn action-options"
      onclick={toggleMoreMenu}
      aria-label={$t('post.more_options')}
      aria-expanded={showMoreMenu}
      aria-haspopup="menu"
    >
      <span class="material-symbols-outlined action-icon">more_horiz</span>
    </button>

    {#if showMoreMenu}
      <div class="more-menu" class:more-menu-upward={menuOpenUpward} role="menu" style:max-height={menuMaxHeight}>
        {#if isRemotePost()}
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleDisplayOnInstance}>
            <span class="material-symbols-outlined menu-icon">open_in_new</span>
            {$t('post.display_on_instance')}
          </button>
        {/if}
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleQuote}>
          <span class="material-symbols-outlined menu-icon">format_quote</span>
          {$t('post.quote_post')}
        </button>
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleShareToGroup}>
          <span class="material-symbols-outlined menu-icon">group_add</span>
          {$t('share_group.menu_item')}
        </button>
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleShare}>
          <span class="material-symbols-outlined menu-icon">share</span>
          {$t('post.share')}
        </button>
        {#if postVideo}
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleDownloadVideo}>
            <span class="material-symbols-outlined menu-icon">download</span>
            {$t('post.download_video')}
          </button>
        {/if}
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleBookmark}>
          <span class="material-symbols-outlined menu-icon">{isBookmarked ? 'bookmark_remove' : 'bookmark'}</span>
          {isBookmarked ? $t('post.remove_bookmark') : $t('post.bookmark')}
        </button>
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleMuteNotifications}>
          <span class="material-symbols-outlined menu-icon">{isPostMuted ? 'notifications_active' : 'notifications_off'}</span>
          {isPostMuted ? $t('post.unmute_notifications') : $t('post.mute_notifications')}
        </button>
        {#if isOwnPost()}
          {#if !isPinned || viewerContext === null || viewerContext === pinScope}
            {@const pinLabel = isPinned
              ? (pinScope === 'group'
                  ? (post.group?.name ? $t('post.unpin_from_named', { name: post.group.name }) : $t('post.unpin_from_group'))
                  : pinScope === 'page'
                    ? (post.page?.name ? $t('post.unpin_from_named', { name: post.page.name }) : $t('post.unpin_from_page'))
                    : $t('post.unpin_from_profile'))
              : (pinScope === 'group'
                  ? (post.group?.name ? $t('post.pin_in_named', { name: post.group.name }) : $t('post.pin_in_group'))
                  : pinScope === 'page'
                    ? (post.page?.name ? $t('post.pin_on_named', { name: post.page.name }) : $t('post.pin_on_page'))
                    : $t('post.pin_to_profile'))}
            <button type="button" class="more-menu-item" role="menuitem" onclick={handlePinToggle}>
              <span class="material-symbols-outlined menu-icon">{isPinned ? 'keep_off' : 'push_pin'}</span>
              {pinLabel}
            </button>
          {/if}
          {#if !post.edit_expires_at || new Date(post.edit_expires_at) > new Date()}
            <button type="button" class="more-menu-item" role="menuitem" onclick={handleEdit}>
              <span class="material-symbols-outlined menu-icon">edit</span>
              {$t('post.edit')}
            </button>
          {/if}
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleDelete}>
            <span class="material-symbols-outlined menu-icon">delete</span>
            {$t('post.delete')}
          </button>
        {/if}
        {#if post.edited_at}
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleViewHistory}>
            <span class="material-symbols-outlined menu-icon">history</span>
            {$t('post.edit_history')}
          </button>
        {/if}
        {#if !isOwnPost()}
          <div class="more-menu-divider"></div>
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleMentionUser}>
            <span class="material-symbols-outlined menu-icon">alternate_email</span>
            {$t('post.mention_user', { handle: post.account.acct || post.account.handle })}
          </button>
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleChatWithUser}>
            <span class="material-symbols-outlined menu-icon">chat</span>
            {$t('post.chat_with', { handle: post.account.acct || post.account.handle })}
          </button>
          <div class="more-menu-divider"></div>
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleMuteUser}>
            <span class="material-symbols-outlined menu-icon">volume_off</span>
            {$t('post.mute_user_named', { handle: post.account.acct || post.account.handle })}
          </button>
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleBlockUser}>
            <span class="material-symbols-outlined menu-icon">block</span>
            {$t('post.block_user_named', { handle: post.account.acct || post.account.handle })}
          </button>
          {#if isRemotePost() && postDomain()}
            <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleBlockDomain}>
              <span class="material-symbols-outlined menu-icon">public_off</span>
              {$t('block.block_domain', { domain: postDomain() })}
            </button>
          {/if}
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleNotInterested}>
            <span class="material-symbols-outlined menu-icon">visibility_off</span>
            {$t('block.not_interested')}
          </button>
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleReport}>
            <span class="material-symbols-outlined menu-icon">flag</span>
            {$t('post.report')}
          </button>
        {/if}
      </div>
    {/if}
    </div>
  </div>
</div>

<ShareToGroupModal bind:open={showShareToGroup} {post} />

{#if showDeleteConfirm}
  <div class="dialog-overlay" onclick={cancelDelete} role="dialog" aria-modal="true" aria-label={$t('post.confirm_delete_label')}>
    <div class="dialog-panel" onclick={(e) => e.stopPropagation()}>
      <h3 class="dialog-title">{$t('post.delete_title')}</h3>
      <p class="dialog-message">{$t('post.delete_message')}</p>
      <div class="dialog-actions">
        <button type="button" class="dialog-cancel" onclick={cancelDelete}>{$t('common.cancel')}</button>
        <button type="button" class="dialog-confirm-danger" onclick={confirmDelete}>{$t('post.delete')}</button>
      </div>
    </div>
  </div>
{/if}

{#if showReportModal}
  <div class="dialog-overlay" onclick={cancelReport} role="dialog" aria-modal="true" aria-label={$t('report.modal_label')}>
    <div class="dialog-panel report-panel" onclick={(e) => e.stopPropagation()}>
      <button
        type="button"
        class="report-close"
        onclick={cancelReport}
        aria-label={$t('report.close')}
        title={$t('report.close')}
      >
        <span class="material-symbols-outlined">close</span>
      </button>

      {#if reportStep === 1}
        <h3 class="dialog-title">{$t('report.step1_title')}</h3>
        <p class="dialog-message">{$t('report.step1_question')}</p>

        <div class="report-form">
          <label class="report-label" for="report-category">{$t('report.category')}</label>
          <select id="report-category" class="report-select" bind:value={reportCategory}>
            {#each reportCategories as cat (cat.value)}
              <option value={cat.value}>{cat.label}</option>
            {/each}
          </select>

          <label class="report-label" for="report-description">{$t('report.description')} <span class="report-optional">{$t('report.optional')}</span></label>
          <textarea
            id="report-description"
            class="report-textarea"
            bind:value={reportDescription}
            placeholder={$t('report.description_placeholder')}
            rows="4"
          ></textarea>

          {#if reportError}
            <p class="report-error">{reportError}</p>
          {/if}
        </div>

        <div class="dialog-actions">
          <button type="button" class="dialog-cancel" onclick={cancelReport}>{$t('common.cancel')}</button>
          <button type="button" class="dialog-confirm" onclick={reportNext}>
            {$t('common.next')}
          </button>
        </div>

      {:else}
        <h3 class="dialog-title">{$t('report.step2_title')}</h3>

        {#if reportIsRemote}
          <div class="report-remote-notice" role="note">
            <span class="material-symbols-outlined" aria-hidden="true">public</span>
            <div>
              <strong>{$t('report.remote_hosted', { domain: reportRemoteDomain })}</strong>
              {$t('report.remote_hosted_detail')}
            </div>
          </div>

          <label class="report-checkbox">
            <input type="checkbox" bind:checked={reportForward} />
            <span>
              <strong>{$t('report.forward', { domain: reportRemoteDomain })}</strong>
              <span class="report-hint">{$t('report.forward_hint')}</span>
            </span>
          </label>
        {/if}

        <label class="report-checkbox">
          <input type="checkbox" bind:checked={reportBlock} />
          <span>
            <strong>{$t('post.block_user_named', { handle: (post.account as any)?.acct || post.account?.handle })}</strong>
            <span class="report-hint">{$t('report.block_hint')}</span>
          </span>
        </label>

        {#if reportError}
          <p class="report-error">{reportError}</p>
        {/if}

        <div class="dialog-actions">
          <button type="button" class="dialog-cancel" onclick={reportBack} disabled={reportSubmitting}>{$t('common.back')}</button>
          <button type="button" class="dialog-confirm-danger" onclick={submitReport} disabled={reportSubmitting}>
            {reportSubmitting ? $t('report.submitting') : $t('report.submit')}
          </button>
        </div>
      {/if}
    </div>
  </div>
{/if}

{#if confirmAction}
  <div class="dialog-overlay" onclick={() => confirmAction = null} role="dialog" aria-modal="true" aria-label={confirmMessages[confirmAction].title}>
    <div class="dialog-panel" onclick={(e) => e.stopPropagation()}>
      <h3 class="dialog-title">{confirmMessages[confirmAction].title}</h3>
      <p class="dialog-message">{confirmMessages[confirmAction].message}</p>
      <div class="dialog-actions">
        <button type="button" class="dialog-cancel" onclick={() => confirmAction = null}>{$t('common.cancel')}</button>
        <button
          type="button"
          class={confirmAction === 'block_user' || confirmAction === 'mute_user' ? 'dialog-confirm-danger' : 'dialog-confirm'}
          onclick={executeConfirmedAction}
        >
          {confirmMessages[confirmAction].button}
        </button>
      </div>
    </div>
  </div>
{/if}

{#if showReactionDetail}
  <div class="reactions-modal-overlay" onclick={() => showReactionDetail = false} role="dialog" aria-modal="true" aria-label={$t('post.reactions')}>
    <div class="reactions-modal" onclick={(e) => e.stopPropagation()}>
      <div class="reactions-modal-header">
        <h3 class="reactions-modal-title">{$t('post.reactions')}</h3>
        <button type="button" class="reactions-modal-close" onclick={() => showReactionDetail = false} aria-label={$t('common.close')}>
          <span class="material-symbols-outlined">close</span>
        </button>
      </div>

      {#if reactionDetailLoading}
        <div class="reactions-modal-loading">{$t('common.loading')}</div>
      {:else}
        <div class="reactions-modal-tabs" role="tablist">
          <button
            type="button"
            role="tab"
            class="reactions-tab"
            class:reactions-tab-active={reactionDetailTab === 'all'}
            onclick={() => reactionDetailTab = 'all'}
          >
            {$t('post.reactions_all')}
          </button>
          {#each reactionDetailData as group (group.type)}
            <button
              type="button"
              role="tab"
              class="reactions-tab"
              class:reactions-tab-active={reactionDetailTab === group.type}
              onclick={() => reactionDetailTab = group.type}
            >
              {@render reactionGlyph(group.type, 'reactions-tab-emoji')}
              <span class="reactions-tab-count">{group.count}</span>
            </button>
          {/each}
        </div>

        <div class="reactions-modal-list">
          {#each reactionDetailData as group (group.type)}
            {#if reactionDetailTab === 'all' || reactionDetailTab === group.type}
              {#each group.accounts as account (account.id)}
                <a href="/@{account.handle}" class="reactions-user" onclick={() => showReactionDetail = false}>
                  <div class="reactions-user-avatar-wrap">
                    {#if account.avatar_url}
                      <img src={account.avatar_url} alt="" class="reactions-user-avatar" />
                    {:else}
                      <div class="reactions-user-avatar reactions-user-avatar-placeholder">
                        {(account.display_name || account.handle).charAt(0).toUpperCase()}
                      </div>
                    {/if}
                    {@render reactionGlyph(group.type, 'reactions-user-emoji')}
                  </div>
                  <div class="reactions-user-info">
                    <span class="reactions-user-name">{account.display_name || account.acct || account.handle}</span>
                    <span class="reactions-user-handle">@{account.acct || account.handle}</span>
                  </div>
                </a>
              {/each}
            {/if}
          {/each}
        </div>
      {/if}
    </div>
  </div>
{/if}

{#if showHistoryModal}
  <div class="reactions-modal-overlay" onclick={() => showHistoryModal = false} role="dialog" aria-modal="true" aria-label={$t('post.edit_history')}>
    <div class="reactions-modal" onclick={(e) => e.stopPropagation()}>
      <div class="reactions-modal-header">
        <h3 class="reactions-modal-title">{$t('post.edit_history_title')}</h3>
        <button type="button" class="reactions-modal-close" onclick={() => showHistoryModal = false} aria-label={$t('common.close')}>
          <span class="material-symbols-outlined">close</span>
        </button>
      </div>

      {#if historyLoading}
        <div class="reactions-modal-loading">{$t('common.loading')}</div>
      {:else if historyData.length === 0}
        <div class="reactions-modal-loading">{$t('post.no_edit_history')}</div>
      {:else}
        <div class="history-list">
          {#each historyData as rev (rev.id)}
            <div class="history-item">
              <div class="history-meta">
                <span class="history-revision">{$t('post.revision', { number: rev.revision_number })}</span>
                <span class="history-date">{new Date(rev.edited_at).toLocaleString()}</span>
              </div>
              <div class="history-content">
                {#if rev.content_html}
                  {@html rev.content_html}
                {:else}
                  <p>{rev.content}</p>
                {/if}
              </div>
            </div>
          {/each}
        </div>
      {/if}
    </div>
  </div>
{/if}

<style>
  /* ---- Action Bar ----
     Two groups: primary controls (like / comment / boost) on the
     start side, social-proof reactions stack + overflow menu on the
     end side. The .post-actions-divider above (in PostCard.svelte)
     supplies the Facebook-style hairline separator. */
  .post-actions {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    gap: 8px;
  }

  .post-actions-left,
  .post-actions-right {
    display: flex;
    align-items: center;
    gap: 2px;
  }

  .action-btn {
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 8px;
    background: transparent;
    border: none;
    border-radius: 9999px;
    color: var(--color-text-secondary);
    font-size: 0.8125rem;
    cursor: pointer;
    transition: color 150ms ease, transform 150ms ease, background-color 150ms ease;
    line-height: 1;
  }

  .action-btn:hover {
    background: var(--color-surface);
  }

  /* On touch devices, extend the tappable area to the 44px minimum without
     changing the button's appearance: a transparent overlay grows only the
     block axis (so adjacent buttons don't overlap across the 2px gap). The
     visible button is untouched — this is a functional hit-target fix, not a
     visual/design change. Coarse-pointer only, so mouse users are unaffected. */
  @media (pointer: coarse) {
    .action-btn::after {
      content: '';
      position: absolute;
      inset-block: -8px;
      inset-inline: 0;
    }
  }

  .action-icon {
    font-size: 20px;
    transition: transform 150ms ease, color 150ms ease;
  }

  .action-btn:hover .action-icon {
    transform: scale(1.1);
  }

  .action-btn:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 1px;
  }

  /* Reply hover */
  .action-reply:hover {
    color: var(--color-primary);
  }

  /* Admin-locked thread: button is non-interactive, grayed out,
     and carries a short inline label so the reason is obvious
     without hovering. The `speaker_notes_off` glyph is the
     chat-bubble with a slash through it — Material's canonical
     "comments disabled" icon, so we don't have to build a
     custom SVG. */
  .action-reply-locked {
    color: var(--color-text-tertiary);
    cursor: not-allowed;
    opacity: 0.6;
  }

  .action-reply-locked:hover {
    color: var(--color-text-tertiary);
    background: transparent;
  }

  .action-locked-label {
    font-size: var(--text-xs);
    font-style: italic;
    margin-inline-start: var(--space-1);
  }

  /* Boost hover + active */
  .action-boost:hover {
    color: var(--color-primary);
  }

  .active-boost {
    color: var(--color-primary);
  }

  /* Like hover + active */
  .action-like:hover {
    color: var(--color-danger);
  }

  .active-reaction {
    color: var(--color-danger);
  }

  /* Share hover */
  .action-options:hover {
    color: var(--color-primary);
  }

  .action-count {
    font-size: var(--text-xs);
    font-weight: 500;
  }

  .current-reaction {
    font-size: 1.125rem;
    line-height: 1;
  }

  .current-reaction-custom {
    width: 20px;
    height: 20px;
    object-fit: contain;
  }

  /* Premium-reaction images. Each render site already has its own
     class (current-reaction, floating-emoji, reactions-tab-emoji,
     reactions-user-emoji, reaction-stack-glyph) that sizes the
     surrounding glyph as text — match those with object-fit so the
     <img> sits at the same visual size as a 1em emoji span. */
  .reaction-glyph-img {
    width: 1.1em;
    height: 1.1em;
    object-fit: contain;
    vertical-align: middle;
  }

  .current-reaction.reaction-glyph-img,
  .floating-emoji.reaction-glyph-img {
    width: 1.25rem;
    height: 1.25rem;
  }

  .reaction-stack-glyph {
    display: inline-flex;
    line-height: 1;
  }
  .reaction-stack-glyph.reaction-glyph-img {
    width: 0.85rem;
    height: 0.85rem;
  }

  .bounce {
    animation: spring-bounce 0.4s ease;
  }

  @keyframes spring-bounce {
    0% { transform: scale(1); }
    30% { transform: scale(1.3); }
    50% { transform: scale(0.9); }
    70% { transform: scale(1.1); }
    100% { transform: scale(1); }
  }

  .floating-emoji {
    position: absolute;
    top: 50%;
    left: 50%;
    font-size: 1.25rem;
    pointer-events: none;
    animation: emoji-snap 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
    z-index: 10;
  }

  @keyframes emoji-snap {
    0% {
      transform: translate(-50%, -50px) scale(1.8);
      opacity: 1;
    }
    50% {
      transform: translate(-50%, -50%) scale(0.7);
      opacity: 1;
    }
    70% {
      transform: translate(-50%, -50%) scale(1.15);
      opacity: 1;
    }
    85% {
      transform: translate(-50%, -50%) scale(0.95);
    }
    100% {
      transform: translate(-50%, -50%) scale(1);
      opacity: 0;
    }
  }

  .action-icon.filled {
    font-variation-settings: 'FILL' 1;
  }

  .action-reply:has(.filled) {
    color: var(--color-primary);
  }

  .action-reaction-wrapper {
    position: relative;
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .action-like {
    position: relative;
    overflow: visible;
    /* The radial picker hijacks long-press + drag on this button.
       Without disabling touch-action, mobile Chrome treats the
       gesture as a scroll and never fires our touchmove updates,
       leaving the dial frozen on the initial touch point. */
    touch-action: none;
    /* Suppress the native long-press menu (Copy / Share / Select all
       on Android, the iOS callout). Combined with preventDefault on
       touchstart this stops the OS from hijacking the gesture
       mid-hold — see Screenshot_20260519_215315. */
    -webkit-user-select: none;
    user-select: none;
    -webkit-touch-callout: none;
  }

  /* ---- Stacked emoji display (right-side social proof) ---- */
  .reaction-stack {
    display: inline-flex;
    align-items: center;
    background: none;
    border: none;
    cursor: pointer;
    padding: 2px 4px;
    border-radius: 9999px;
    transition: background 150ms ease;
  }

  .reaction-stack:hover {
    background: var(--color-surface);
  }

  .reaction-stack-emojis {
    display: flex;
    align-items: center;
    flex-direction: row-reverse;
  }

  .reaction-stack-emoji {
    line-height: 1;
    margin-inline-start: -5px;
    background: var(--color-surface-container-lowest);
    border: 1.5px solid var(--color-surface-container-lowest);
    border-radius: 50%;
    width: 18px;
    height: 18px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.7rem;
    position: relative;
    box-shadow: 0 0 0 0.5px rgba(0, 0, 0, 0.08);
  }

  .reaction-stack-emoji:last-child {
    margin-inline-start: 0;
  }

  /* ---- Reactions Modal ---- */
  .reactions-modal-overlay {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    animation: overlay-fade-in 0.15s ease;
  }

  @keyframes overlay-fade-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .reactions-modal {
    background: var(--color-surface-container-lowest);
    border-radius: 18px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.15);
    width: 90%;
    max-width: 400px;
    max-height: 70vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    animation: modal-scale-in 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes modal-scale-in {
    from { opacity: 0; transform: scale(0.95) translateY(8px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .reactions-modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 18px 20px 12px;
  }

  .reactions-modal-title {
    font-size: 1.125rem;
    font-weight: 700;
    color: var(--color-text);
  }

  .reactions-modal-close {
    background: none;
    border: none;
    color: var(--color-text-secondary);
    cursor: pointer;
    padding: 4px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    transition: background 150ms ease;
  }

  .reactions-modal-close:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .reactions-modal-close .material-symbols-outlined {
    font-size: 22px;
  }

  .reactions-modal-loading {
    padding: 32px;
    text-align: center;
    color: var(--color-text-tertiary);
    font-size: 0.875rem;
  }

  /* Tabs */
  .reactions-modal-tabs {
    display: flex;
    gap: 0;
    padding: 0 20px;
    border-bottom: 2px solid var(--color-border);
    overflow-x: auto;
  }

  .reactions-tab {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 8px 14px;
    background: none;
    border: none;
    border-bottom: 2px solid transparent;
    margin-bottom: -2px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text-secondary);
    cursor: pointer;
    white-space: nowrap;
    transition: color 150ms ease, border-color 150ms ease;
  }

  .reactions-tab:hover {
    color: var(--color-text);
  }

  .reactions-tab-active {
    color: var(--color-primary);
    border-bottom-color: var(--color-primary);
  }

  .reactions-tab-emoji {
    font-size: 1rem;
  }

  .reactions-tab-count {
    font-size: 0.75rem;
    font-weight: 700;
  }

  /* User list */
  .reactions-modal-list {
    flex: 1;
    overflow-y: auto;
    padding: 8px 12px 16px;
  }

  .reactions-user {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px;
    border-radius: 12px;
    text-decoration: none;
    color: var(--color-text);
    transition: background 150ms ease;
  }

  .reactions-user:hover {
    background: var(--color-surface);
  }

  .reactions-user-avatar-wrap {
    position: relative;
    flex-shrink: 0;
  }

  .reactions-user-avatar {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    object-fit: cover;
    display: block;
  }

  .reactions-user-avatar-placeholder {
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-size: 1rem;
    font-weight: 700;
  }

  .reactions-user-emoji {
    position: absolute;
    bottom: -2px;
    inset-inline-end: -4px;
    font-size: 0.875rem;
    background: var(--color-surface-container-lowest);
    border-radius: 50%;
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  }

  .reactions-user-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .reactions-user-name {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
  }

  .reactions-user-handle {
    font-size: 0.75rem;
    color: var(--color-text-secondary);
  }

  /* History modal */
  .history-list {
    padding: 0 16px 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    max-height: 50vh;
    overflow-y: auto;
  }

  .history-item {
    padding: 12px;
    background: var(--color-surface);
    border-radius: 10px;
    border: 1px solid var(--color-border);
  }

  .history-meta {
    display: flex;
    justify-content: space-between;
    margin-block-end: 8px;
    font-size: 0.75rem;
  }

  .history-revision {
    font-weight: 700;
    color: var(--color-primary);
  }

  .history-date {
    color: var(--color-text-tertiary);
  }

  .history-content {
    font-size: 0.875rem;
    color: var(--color-text);
    line-height: 1.5;
  }

  .history-content :global(p) {
    margin: 0;
  }

  .picker-anchor {
    position: absolute;
    inset-block-end: 100%;
    inset-inline-start: 50%;
    transform: translateX(-50%);
    margin-block-end: 8px;
    z-index: var(--z-dropdown);
  }

  /* Flip below the trigger when there isn't enough room above —
     keeps the picker fully visible on posts pinned near the top of
     the viewport (a single post page, the first feed item, etc.). */
  .picker-anchor-below {
    inset-block-end: auto;
    inset-block-start: 100%;
    margin-block-end: 0;
    margin-block-start: 8px;
  }

  .action-more-wrapper {
    position: relative;
  }

  /* ---- More Menu ---- */
  .more-menu {
    position: absolute;
    inset-block-start: 100%;
    inset-inline-end: 0;
    margin-block-start: 4px;
    min-width: 200px;
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 14px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.08);
    padding: 6px;
    /* Above --z-sticky (20) so the menu paints over the BottomTabs
       bar on mobile instead of behind it — the runtime cap on
       max-height keeps the menu from running into the bar visually. */
    z-index: 25;
    overflow-y: auto;
    overscroll-behavior: contain;
    animation: menu-roll-down 0.2s ease;
    transform-origin: top right;
  }

  .more-menu-upward {
    inset-block-start: auto;
    inset-block-end: 100%;
    margin-block-start: 0;
    margin-block-end: 4px;
    animation: menu-roll-up 0.2s ease;
    transform-origin: bottom right;
  }

  @keyframes menu-roll-up {
    from {
      opacity: 0;
      transform: scaleY(0.6) translateY(4px);
    }
    to {
      opacity: 1;
      transform: scaleY(1) translateY(0);
    }
  }

  @keyframes menu-roll-down {
    from {
      opacity: 0;
      transform: scaleY(0.6) translateY(-4px);
    }
    to {
      opacity: 1;
      transform: scaleY(1) translateY(0);
    }
  }

  .more-menu-item {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 10px 14px;
    background: transparent;
    border: none;
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    cursor: pointer;
    text-align: start;
    transition: background-color 150ms ease;
  }

  .menu-icon {
    font-size: 18px;
    color: var(--color-text-secondary);
  }

  .more-menu-item:hover {
    background: var(--color-surface);
  }

  .more-menu-danger {
    color: var(--color-danger);
  }

  .more-menu-danger .menu-icon {
    color: var(--color-danger);
  }

  .more-menu-danger:hover {
    background: var(--color-danger-soft);
  }

  .more-menu-divider {
    height: 1px;
    background: var(--color-border);
    margin: 4px 8px;
  }

  .dialog-confirm {
    padding: 8px 20px;
    border: none;
    border-radius: 9999px;
    background: var(--color-primary);
    color: white;
    font-size: 0.875rem;
    font-weight: 700;
    cursor: pointer;
    transition: opacity 150ms ease;
  }

  .dialog-confirm:hover {
    opacity: 0.9;
  }

  /* ---- Dialog Overlay ---- */
  .dialog-overlay {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    animation: overlay-in 0.15s ease;
  }

  @keyframes overlay-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes dialog-in {
    from { opacity: 0; transform: scale(0.95) translateY(4px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .dialog-panel {
    background: var(--color-surface-container-lowest);
    border-radius: 18px;
    padding: 28px;
    max-width: 400px;
    width: 90%;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.15);
    animation: dialog-in 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .dialog-title {
    font-size: 1.125rem;
    font-weight: 700;
    margin-block-end: 8px;
  }

  .dialog-message {
    font-size: 0.875rem;
    color: var(--color-text-secondary);
    margin-block-end: 20px;
    line-height: 1.5;
  }

  .dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: 12px;
  }

  .dialog-cancel {
    padding: 8px 20px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: transparent;
    color: var(--color-text);
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 150ms ease;
  }

  .dialog-cancel:hover {
    background: var(--color-surface);
  }

  .dialog-confirm-danger {
    padding: 8px 20px;
    border: none;
    border-radius: 9999px;
    background: var(--color-danger);
    color: white;
    font-size: 0.875rem;
    font-weight: 700;
    cursor: pointer;
    transition: opacity 150ms ease;
  }

  .dialog-confirm-danger:hover {
    opacity: 0.9;
  }

  .dialog-confirm-danger:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* ---- Report Form ---- */
  .report-form {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-block-end: 20px;
  }

  .report-label {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
  }

  .report-select {
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
  }

  .report-textarea {
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
    resize: vertical;
    font-family: inherit;
  }

  .report-error {
    font-size: 0.875rem;
    color: var(--color-danger);
  }

  .report-optional {
    color: var(--color-text-tertiary);
    font-weight: 400;
  }

  .report-remote-notice {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    padding: 12px 14px;
    border-radius: 10px;
    background: var(--color-primary-soft);
    color: var(--color-text);
    font-size: 0.875rem;
    line-height: 1.5;
    margin-block-end: 16px;
  }

  .report-remote-notice :global(.material-symbols-outlined) {
    color: var(--color-primary);
    font-size: 20px;
    flex-shrink: 0;
    margin-top: 1px;
  }

  .report-checkbox {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    padding: 12px 14px;
    border: 1px solid var(--color-border);
    border-radius: 10px;
    margin-block-end: 10px;
    cursor: pointer;
    transition: background 0.15s ease;
  }

  .report-checkbox:hover {
    background: var(--color-surface);
  }

  .report-checkbox input[type="checkbox"] {
    margin-top: 3px;
    flex-shrink: 0;
  }

  .report-checkbox strong {
    display: block;
    font-weight: 600;
    font-size: 0.875rem;
    color: var(--color-text);
  }


  .report-hint {
    display: block;
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
    margin-block-start: 2px;
    font-weight: 400;
  }

  /* Report dialog gets some top padding so the absolute-positioned
     close button doesn't crowd the title. */
  .report-panel {
    position: relative;
    padding-block-start: 44px;
  }

  .report-close {
    position: absolute;
    top: 10px;
    inset-inline-end: 10px;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    border-radius: 9999px;
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background 0.15s ease, color 0.15s ease;
  }

  .report-close:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .report-close :global(.material-symbols-outlined) {
    font-size: 20px;
  }
</style>

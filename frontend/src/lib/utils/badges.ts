/**
 * Badge filtering shared between every surface that renders an
 * account's identity (ProfileHeader, PostCard, hover cards, etc.).
 *
 * Rule: only the *highest* verified-tier badge a user owns should
 * render. Stacking L1+L2+L3 next to a basic Verified mark made the
 * UI look like a sticker collection. Role badges (owner / admin /
 * moderator / bot) are orthogonal to tier and stay.
 *
 * If any tier badge is present, the basic VerifiedBadge is also
 * suppressed — the tier glyph already implies verification, so a
 * separate ✓ would just be a duplicate next to it.
 */

export type BadgeType =
  | 'bot'
  | 'admin'
  | 'owner'
  | 'moderator'
  | 'editor'
  | 'verified_l0'
  | 'verified_l1'
  | 'verified_l2'
  | 'verified_l3';

export interface Badge {
  type: BadgeType;
  label?: string;
}

const TIER_RANK: Record<string, number> = {
  verified_l0: 0.5,
  verified_l1: 1,
  verified_l2: 2,
  verified_l3: 3,
};

export interface FilteredBadges {
  /** All non-tier badges (owner/admin/moderator/bot/etc.) in order. */
  nonTier: Badge[];
  /** The single highest-tier badge, or null if the user has none. */
  highestTier: Badge | null;
  /** Whether the basic verified ✓ should still show. */
  showVerifiedMark: boolean;
}

export function filterBadges(badges: Badge[] | undefined | null, isVerified: boolean): FilteredBadges {
  const list = badges ?? [];
  let highestTier: Badge | null = null;
  let bestRank = 0;
  const nonTier: Badge[] = [];
  // Several badges can share a type: on a group/page post the backend adds
  // a context badge ("Admin of X") next to the instance one ("Admin").
  // Renderers key by type+label, so drop only exact repeats.
  const seen = new Set<string>();

  for (const b of list) {
    const rank = TIER_RANK[b.type] ?? 0;
    if (rank === 0) {
      const key = `${b.type}:${b.label ?? ''}`;
      if (seen.has(key)) continue;
      seen.add(key);
      nonTier.push(b);
      continue;
    }
    if (rank > bestRank) {
      highestTier = b;
      bestRank = rank;
    }
  }

  return {
    nonTier,
    highestTier,
    showVerifiedMark: !!isVerified && !highestTier,
  };
}

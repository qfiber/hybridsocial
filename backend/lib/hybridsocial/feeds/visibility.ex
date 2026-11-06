defmodule Hybridsocial.Feeds.Visibility do
  @moduledoc """
  Visibility enforcement for posts.
  Provides functions to check post visibility and apply query-level filters
  for blocks, mutes, and visibility rules.
  """
  import Ecto.Query

  alias Hybridsocial.Social.{Follow, Block, Mute, PostMention, ListMember}
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Moderation.BlockedHashtag
  alias Hybridsocial.Repo

  @doc """
  Checks if a specific post is visible to a viewer.

  - public: always visible
  - followers: viewer must follow the author
  - direct: viewer must be in post_recipients (stub - returns false for now)
  - list: viewer must be in the associated list (stub - returns false for now)
  - group: viewer must be a group member (stub - returns true for now)
  """
  def visible_to?(_post, nil), do: false

  def visible_to?(post, viewer_identity_id) do
    # Author can always see their own posts
    if post.identity_id == viewer_identity_id do
      true
    else
      check_visibility(post, viewer_identity_id)
    end
  end

  defp check_visibility(%{visibility: vis}, _viewer_id) when vis in ["public", "unlisted"],
    do: true

  defp check_visibility(%{visibility: "followers", identity_id: author_id}, viewer_id) do
    Follow
    |> where(
      [f],
      f.follower_id == ^viewer_id and
        f.followee_id == ^author_id and
        f.status == :accepted
    )
    |> Repo.exists?()
  end

  defp check_visibility(%{visibility: "direct", id: post_id}, viewer_id) do
    PostMention
    |> where([pm], pm.post_id == ^post_id and pm.identity_id == ^viewer_id)
    |> Repo.exists?()
  end

  defp check_visibility(%{visibility: "list", list_id: list_id}, viewer_id)
       when not is_nil(list_id) do
    ListMember
    |> where([m], m.list_id == ^list_id and m.target_identity_id == ^viewer_id)
    |> Repo.exists?()
  end

  defp check_visibility(%{visibility: "list"}, _viewer_id), do: false

  defp check_visibility(%{visibility: "group", group_id: group_id}, viewer_id)
       when not is_nil(group_id) do
    Hybridsocial.Groups.member?(group_id, viewer_id)
  end

  defp check_visibility(%{visibility: "group"}, _viewer_id), do: false

  defp check_visibility(_post, _viewer_id), do: false

  @doc """
  Applies visibility filtering to an Ecto query.
  Returns posts that the viewer is allowed to see.

  When viewer_identity_id is nil (unauthenticated), only public posts are returned.
  """
  def apply_visibility_filter(query, nil) do
    where(query, [p], p.visibility == "public")
  end

  def apply_visibility_filter(query, viewer_identity_id) do
    apply_post_visibility(query, viewer_identity_id)
  end

  @doc """
  Comprehensive visibility filter that mirrors `viewer_can_read?/2` in
  query form. Use this anywhere a query may surface posts of any
  visibility (profile feeds, search, federation, list timelines).

  Includes:
    * public / unlisted — everyone (subject to other filters)
    * the viewer's own posts — any visibility
    * followers — only posts from accounts the viewer follows
    * direct — only posts where the viewer is in `post_mentions`
    * list — only posts whose list_id has the viewer in `list_members`
    * group — only posts whose group has the viewer as a member

  When `viewer_id` is nil, only public/unlisted posts pass.
  """
  def apply_post_visibility(query, nil) do
    where(query, [p], p.visibility in ["public", "unlisted"])
  end

  def apply_post_visibility(query, viewer_id) do
    followed_ids_subquery =
      Follow
      |> where([f], f.follower_id == ^viewer_id and f.status == :accepted)
      |> select([f], f.followee_id)

    mentioned_post_ids =
      PostMention
      |> where([pm], pm.identity_id == ^viewer_id)
      |> select([pm], pm.post_id)

    list_ids_subquery =
      ListMember
      |> where([m], m.target_identity_id == ^viewer_id)
      |> select([m], m.list_id)

    group_ids_subquery =
      from(gm in "group_members",
        where: gm.identity_id == type(^viewer_id, Ecto.UUID),
        select: gm.group_id
      )

    where(
      query,
      [p],
      p.identity_id == ^viewer_id or
        p.visibility in ["public", "unlisted"] or
        (p.visibility == "followers" and p.identity_id in subquery(followed_ids_subquery)) or
        (p.visibility == "direct" and p.id in subquery(mentioned_post_ids)) or
        (p.visibility == "list" and not is_nil(p.list_id) and
           p.list_id in subquery(list_ids_subquery)) or
        (p.visibility == "group" and not is_nil(p.group_id) and
           p.group_id in subquery(group_ids_subquery))
    )
  end

  @doc """
  Excludes posts from accounts that have blocked the viewer or that the viewer has blocked.
  Both directions are filtered: if A blocks B, neither sees the other's posts.
  """
  def apply_block_filter(query, nil), do: query

  def apply_block_filter(query, viewer_identity_id) do
    blocked_by_viewer =
      Block
      |> where([b], b.blocker_id == ^viewer_identity_id)
      |> select([b], b.blocked_id)

    blocked_viewer =
      Block
      |> where([b], b.blocked_id == ^viewer_identity_id)
      |> select([b], b.blocker_id)

    query
    |> where([p], p.identity_id not in subquery(blocked_by_viewer))
    |> where([p], p.identity_id not in subquery(blocked_viewer))
  end

  @doc """
  Excludes posts from accounts the viewer has muted.
  Respects mute expiration.
  """
  def apply_mute_filter(query, nil), do: query

  def apply_mute_filter(query, viewer_identity_id) do
    now = DateTime.utc_now()

    muted_ids =
      Mute
      |> where([m], m.muter_id == ^viewer_identity_id)
      |> where([m], is_nil(m.expires_at) or m.expires_at > ^now)
      |> select([m], m.muted_id)

    where(query, [p], p.identity_id not in subquery(muted_ids))
  end

  @doc """
  Excludes posts by locked accounts when nobody is logged in, because a locked
  account is private to anonymous viewers. See `Accounts.hidden_from_viewer?/2`.

  Anything shared between viewers, like the prewarmed snapshots, is built for
  logged-in members too and must not use this. Anonymous requests skip those.
  """
  def exclude_locked_for_anonymous(query, nil) do
    where(query, [p], p.identity_id not in subquery(locked_account_ids()))
  end

  def exclude_locked_for_anonymous(query, _viewer_id), do: query

  @doc "Of the given identity ids, the locked ones, as a MapSet."
  def locked_among(identity_ids) do
    locked_account_ids() |> where([i], i.id in ^identity_ids) |> Repo.all() |> MapSet.new()
  end

  defp locked_account_ids do
    Identity |> where([i], i.is_locked == true) |> select([i], i.id)
  end

  @doc """
  Excludes posts from silenced accounts on public/global timelines.
  Silenced users' posts are hidden from public timelines but remain visible
  to their followers. Respects silenced_until expiry.
  """
  def apply_silence_filter(query) do
    now = DateTime.utc_now()

    silenced_ids =
      Identity
      |> where(
        [i],
        i.is_silenced == true and
          (is_nil(i.silenced_until) or i.silenced_until > ^now)
      )
      |> select([i], i.id)

    query
    |> where([p], p.identity_id not in subquery(silenced_ids))
    |> where([p], p.identity_id not in subquery(authors_on_domains_under("silence")))
  end

  @doc """
  Excludes posts by suspended accounts and by remote authors on a domain under
  a `suspend` instance policy. Unlike silence this applies to every feed,
  followers included.

  This is a read-time filter on purpose: suspending takes effect on posts we
  already hold, and lifting it brings them back. Deleting them for good is the
  separate, explicit `Federation.Cleanup.purge_instance_content/2`.
  """
  def apply_suspension_filter(query) do
    query
    |> where([p], p.identity_id not in subquery(suspended_account_ids()))
    |> where([p], p.identity_id not in subquery(authors_on_domains_under("suspend")))
  end

  @doc """
  `apply_suspension_filter/1` for a Boost query joined to its Post as the second
  binding. Drops the boost when either the booster or the boosted author is
  suspended, since a boost would otherwise carry a suspended post into a feed.
  """
  def apply_boost_suspension_filter(query) do
    query
    |> where([b, _p], b.identity_id not in subquery(suspended_account_ids()))
    |> where([b, _p], b.identity_id not in subquery(authors_on_domains_under("suspend")))
    |> where([_b, p], p.identity_id not in subquery(suspended_account_ids()))
    |> where([_b, p], p.identity_id not in subquery(authors_on_domains_under("suspend")))
  end

  @doc """
  Excludes posts carrying a hashtag blocked with `hide` or `reject`. For public
  surfaces only: followers of the author still see these posts at home.
  """
  def apply_blocked_hashtag_filter(query) do
    hiding_actions = BlockedHashtag.hiding_actions()

    where(
      query,
      [p],
      fragment(
        "NOT EXISTS (SELECT 1 FROM post_hashtags ph JOIN hashtags h ON h.id = ph.hashtag_id JOIN blocked_hashtags bh ON bh.name = h.name WHERE ph.post_id = ? AND bh.action = ANY(?))",
        p.id,
        ^hiding_actions
      )
    )
  end

  @doc """
  Every identity whose posts must not count towards public surfaces such as
  trending: suspended, silenced or shadow-banned accounts, and remote authors on
  a suspended or silenced domain.
  """
  def publicly_hidden_author_ids do
    now = DateTime.utc_now()

    Identity
    |> where(
      [i],
      i.is_suspended == true or i.is_shadow_banned == true or
        (i.is_silenced == true and (is_nil(i.silenced_until) or i.silenced_until > ^now)) or
        (i.is_local == false and
           fragment(
             "lower(split_part(split_part(?, '/', 3), ':', 1)) IN (SELECT domain FROM instance_policies WHERE policy IN ('suspend', 'silence'))",
             i.ap_actor_url
           ))
    )
    |> select([i], i.id)
  end

  @doc """
  Of the given identity ids, the ones that are suspended, whether individually or
  through their domain. One query per source however many ids there are, for
  lists like a thread's replies where checking each author would be N+1.
  """
  def suspended_among(identity_ids) do
    [suspended_account_ids(), authors_on_domains_under("suspend")]
    |> Enum.flat_map(fn query ->
      query |> where([i], i.id in ^identity_ids) |> Repo.all()
    end)
    |> MapSet.new()
  end

  defp suspended_account_ids do
    Identity
    |> where([i], i.is_suspended == true)
    |> select([i], i.id)
  end

  # Remote identities carry no domain column, so the host comes from
  # `ap_actor_url`. This expression must stay identical to the one in the
  # `identities_remote_host_index` migration or the index stops being used.
  #
  # `is_local` matters: actors imported from a migrated instance keep their old
  # `ap_actor_url` but live here, so a policy on the old host must not hide them.
  defp authors_on_domains_under(policy) do
    Identity
    |> where([i], i.is_local == false)
    |> where(
      [i],
      fragment(
        "lower(split_part(split_part(?, '/', 3), ':', 1)) IN (SELECT domain FROM instance_policies WHERE policy::text = ?)",
        i.ap_actor_url,
        ^policy
      )
    )
    |> select([i], i.id)
  end

  @doc """
  Excludes posts from shadow-banned accounts. Shadow-banned users can only
  see their own posts — everyone else should not see them.

  When viewer_id is nil (unauthenticated), all shadow-banned posts are excluded.
  When viewer_id matches the post author, the post is kept (the shadow-banned
  user can see their own content).
  """
  def apply_shadow_ban_filter(query, nil) do
    shadow_banned_ids =
      Identity
      |> where([i], i.is_shadow_banned == true)
      |> select([i], i.id)

    where(query, [p], p.identity_id not in subquery(shadow_banned_ids))
  end

  def apply_shadow_ban_filter(query, viewer_identity_id) do
    shadow_banned_ids =
      Identity
      |> where([i], i.is_shadow_banned == true)
      |> select([i], i.id)

    where(
      query,
      [p],
      p.identity_id == ^viewer_identity_id or
        p.identity_id not in subquery(shadow_banned_ids)
    )
  end
end

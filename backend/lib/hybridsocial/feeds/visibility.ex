defmodule Hybridsocial.Feeds.Visibility do
  @moduledoc """
  Visibility enforcement for posts.
  Provides functions to check post visibility and apply query-level filters
  for blocks, mutes, and visibility rules.
  """
  import Ecto.Query

  alias Hybridsocial.Social.{Follow, Block, Mute}

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

  defp check_visibility(%{visibility: "public"}, _viewer_id), do: true

  defp check_visibility(%{visibility: "followers", identity_id: author_id}, viewer_id) do
    alias Hybridsocial.Repo

    Follow
    |> where(
      [f],
      f.follower_id == ^viewer_id and
        f.followee_id == ^author_id and
        f.status == :accepted
    )
    |> Repo.exists?()
  end

  defp check_visibility(%{visibility: "direct"}, _viewer_id) do
    # Stub: post_recipients table does not exist yet.
    # When it does, check if viewer_id is in post_recipients for this post.
    false
  end

  defp check_visibility(%{visibility: "list"}, _viewer_id) do
    # Stub: check if viewer is in the associated list.
    false
  end

  defp check_visibility(%{visibility: "group"}, _viewer_id) do
    # Stub: group membership check not implemented yet.
    true
  end

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
    followed_ids_subquery =
      Follow
      |> where([f], f.follower_id == ^viewer_identity_id and f.status == :accepted)
      |> select([f], f.followee_id)

    where(
      query,
      [p],
      p.visibility == "public" or
        p.identity_id == ^viewer_identity_id or
        (p.visibility == "followers" and p.identity_id in subquery(followed_ids_subquery)) or
        p.visibility == "group"
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
end

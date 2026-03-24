defmodule Hybridsocial.Feeds.Algorithms.Chronological do
  @moduledoc """
  Chronological timeline algorithm.

  Returns posts from followed accounts and own posts in strict reverse-chronological
  order, merged with boosts from followed accounts. This is the default algorithm
  and does not apply any scoring or ranking.
  """
  @behaviour Hybridsocial.Feeds.TimelineAlgorithm

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Post, Follow, Boost}
  alias Hybridsocial.Feeds.Visibility
  alias Hybridsocial.Feeds

  @default_limit 20
  @max_limit 40

  @impl true
  def name, do: "chronological"

  @impl true
  def score_post(_post, _context), do: 0.0

  @impl true
  def home_feed(identity_id, opts) do
    limit = parse_limit(opts)

    # Subquery: IDs of accounts the viewer follows
    followed_ids =
      Follow
      |> where([f], f.follower_id == ^identity_id and f.status == :accepted)
      |> select([f], f.followee_id)

    # Original posts from followed accounts + own posts
    posts_query =
      Post
      |> where([p], p.identity_id in subquery(followed_ids) or p.identity_id == ^identity_id)
      |> where([p], is_nil(p.deleted_at))
      |> apply_cursor_filters(opts)
      |> Visibility.apply_block_filter(identity_id)
      |> Visibility.apply_mute_filter(identity_id)
      |> Visibility.apply_shadow_ban_filter(identity_id)
      |> order_by([p], desc: p.inserted_at)
      |> limit(^limit)
      |> preload(:identity)
      |> Repo.all()

    # Boosts from followed accounts
    boosts =
      Boost
      |> where([b], b.identity_id in subquery(followed_ids) or b.identity_id == ^identity_id)
      |> where([b], is_nil(b.deleted_at))
      |> join(:inner, [b], p in Post, on: b.post_id == p.id and is_nil(p.deleted_at))
      |> apply_boost_cursor_filters(opts)
      |> order_by([b], desc: b.inserted_at)
      |> limit(^limit)
      |> preload([b, p], post: {p, :identity})
      |> preload(:identity)
      |> Repo.all()

    # Merge posts and boosts, sort by inserted_at descending, take limit
    Feeds.merge_timeline_entries(posts_query, boosts)
    |> Enum.take(limit)
  end

  # --- Private helpers ---

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp apply_cursor_filters(query, opts) do
    query
    |> maybe_max_id(Keyword.get(opts, :max_id))
    |> maybe_min_id(Keyword.get(opts, :min_id))
    |> maybe_since_id(Keyword.get(opts, :since_id))
  end

  defp maybe_max_id(query, nil), do: query
  defp maybe_max_id(query, max_id), do: where(query, [p], p.id < ^max_id)

  defp maybe_min_id(query, nil), do: query
  defp maybe_min_id(query, min_id), do: where(query, [p], p.id > ^min_id)

  defp maybe_since_id(query, nil), do: query
  defp maybe_since_id(query, since_id), do: where(query, [p], p.id > ^since_id)

  defp apply_boost_cursor_filters(query, opts) do
    query
    |> maybe_boost_max_id(Keyword.get(opts, :max_id))
    |> maybe_boost_min_id(Keyword.get(opts, :min_id))
  end

  defp maybe_boost_max_id(query, nil), do: query
  defp maybe_boost_max_id(query, max_id), do: where(query, [b], b.id < ^max_id)

  defp maybe_boost_min_id(query, nil), do: query
  defp maybe_boost_min_id(query, min_id), do: where(query, [b], b.id > ^min_id)
end

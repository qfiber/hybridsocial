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
  alias Hybridsocial.Social.{Post, Follow, Boost, FollowedTag}
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
    # Resolve the cursor *once* from the cursor's post id. Both the
    # post and the boost queries paginate against the same instant,
    # so a single lookup keeps the page coherent.
    cursor = resolve_cursor(opts)

    # Subquery: IDs of accounts the viewer follows
    followed_ids =
      Follow
      |> where([f], f.follower_id == ^identity_id and f.status == :accepted)
      |> select([f], f.followee_id)

    # Followed hashtag IDs
    followed_tag_ids =
      FollowedTag
      |> where([ft], ft.identity_id == ^identity_id)
      |> select([ft], ft.hashtag_id)

    # Post IDs from followed hashtags
    tagged_post_ids =
      from(ph in "post_hashtags",
        where: ph.hashtag_id in subquery(followed_tag_ids),
        select: ph.post_id
      )

    # Original posts from followed accounts + own posts + followed tags.
    # `apply_post_visibility` is the per-post audience gate: it keeps
    # public/unlisted plus followers-only when the viewer follows the
    # author, plus direct/list/group when the viewer is a recipient
    # / member, plus the viewer's own posts at any visibility. Without
    # this, a followed user's direct DMs to a third party would leak
    # into every follower's home feed.
    posts_query =
      Post
      |> where(
        [p],
        p.identity_id in subquery(followed_ids) or
          p.identity_id == ^identity_id or
          p.id in subquery(tagged_post_ids)
      )
      |> where([p], is_nil(p.deleted_at))
      |> where([p], not is_nil(p.published_at))
      |> where([p], is_nil(p.parent_id))
      |> apply_post_cursor(cursor)
      |> Visibility.apply_post_visibility(identity_id)
      |> Visibility.apply_block_filter(identity_id)
      |> Visibility.apply_mute_filter(identity_id)
      |> Visibility.apply_shadow_ban_filter(identity_id)
      |> Visibility.apply_suspension_filter()
      # `id DESC` is the explicit tie-breaker for posts inserted in
      # the same instant; without it the row-tuple cursor below
      # couldn't deterministically pick a "next page" boundary.
      |> order_by([p], desc: p.inserted_at, desc: p.id)
      |> limit(^limit)
      |> preload([:identity, :quote])
      |> Repo.all()

    # Boosts from followed accounts
    boosts =
      Boost
      |> where([b], b.identity_id in subquery(followed_ids) or b.identity_id == ^identity_id)
      |> where([b], is_nil(b.deleted_at))
      |> join(:inner, [b], p in Post, on: b.post_id == p.id and is_nil(p.deleted_at))
      |> Visibility.apply_boost_suspension_filter()
      |> apply_boost_cursor(cursor)
      |> order_by([b], desc: b.inserted_at)
      |> limit(^limit)
      |> preload([b, p], post: {p, [:identity, :quote]})
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

  # Resolve the client's cursor (max_id / min_id / since_id) into a
  # boundary {direction, inserted_at, id}. The cursor must reference a
  # row in `posts` — feed entries can be either Posts or Boosts, but
  # only the post id paired with its inserted_at gives us a stable
  # ordering anchor for both queries to share.
  #
  # Returns nil when no cursor was sent OR the cursor doesn't resolve
  # (stale client, boost id leaking through, etc.) — both branches
  # fall back to the latest page rather than an empty one.
  defp resolve_cursor(opts) do
    cond do
      max_id = Keyword.get(opts, :max_id) ->
        case lookup_post_cursor(max_id),
          do: (
            nil -> nil
            {ia, id} -> {:older, ia, id}
          )

      min_id = Keyword.get(opts, :min_id) ->
        case lookup_post_cursor(min_id),
          do: (
            nil -> nil
            {ia, id} -> {:newer, ia, id}
          )

      since_id = Keyword.get(opts, :since_id) ->
        case lookup_post_cursor(since_id),
          do: (
            nil -> nil
            {ia, id} -> {:newer, ia, id}
          )

      true ->
        nil
    end
  end

  defp lookup_post_cursor(id) when is_binary(id) do
    case Repo.one(from p in Post, where: p.id == ^id, select: {p.inserted_at, p.id}) do
      nil -> nil
      {ia, pid} -> {ia, pid}
    end
  end

  defp lookup_post_cursor(_), do: nil

  defp apply_post_cursor(query, nil), do: query

  defp apply_post_cursor(query, {:older, ia, id}) do
    where(query, [p], fragment("(?, ?) < (?, ?)", p.inserted_at, p.id, ^ia, type(^id, Ecto.UUID)))
  end

  defp apply_post_cursor(query, {:newer, ia, id}) do
    where(query, [p], fragment("(?, ?) > (?, ?)", p.inserted_at, p.id, ^ia, type(^id, Ecto.UUID)))
  end

  # Boost cursor filters by inserted_at only — boost ids and post ids
  # live in different tables, so a row-tuple comparison would mix
  # incompatible UUIDs. We accept that boosts inserted in the exact
  # same microsecond as the boundary post may be re-shown; the
  # render-layer dedupe in FeedList catches that case in practice.
  defp apply_boost_cursor(query, nil), do: query

  defp apply_boost_cursor(query, {:older, ia, _id}) do
    where(query, [b], b.inserted_at < ^ia)
  end

  defp apply_boost_cursor(query, {:newer, ia, _id}) do
    where(query, [b], b.inserted_at > ^ia)
  end
end

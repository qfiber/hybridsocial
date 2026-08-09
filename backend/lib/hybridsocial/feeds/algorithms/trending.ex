defmodule Hybridsocial.Feeds.Algorithms.Trending do
  @moduledoc """
  Trending timeline algorithm.

  Returns popular public posts from a configurable time window, scored by
  a multi-factor engagement formula:

  1. **Raw engagement** — reactions + boosts × 2 + replies × 1.5
  2. **Velocity bonus** — engagement concentrated in a short burst scores higher
  3. **Underdog bonus** — posts with high engagement relative to their author's
     follower count get a boost (viral from small accounts)
  4. **Time decay** — exponential decay, halving roughly every 24 hours
  5. **Author diversity** — at most 2 posts per author in the final feed

  The trending window (default 24h) is configurable via the
  `trending_window_hours` admin setting.
  """
  @behaviour Hybridsocial.Feeds.TimelineAlgorithm

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.{Follow, Post}
  alias Hybridsocial.Feeds.Visibility

  @default_limit 20
  @max_limit 40
  @default_window_hours 24
  # Max posts per author in final feed
  @max_per_author 2
  # Fetch more candidates than needed to allow diversity filtering
  @candidate_multiplier 5

  @impl true
  def name, do: "trending"

  @impl true
  def score_post(post, context) do
    now = Map.get(context, :now, DateTime.utc_now())
    follower_counts = Map.get(context, :follower_counts, %{})
    # Floor at 30 min so a brand-new post can't manufacture an enormous
    # velocity (engagement / age) and leapfrog genuinely engaged posts.
    age_hours = max(DateTime.diff(now, post.inserted_at, :second) / 3600.0, 0.5)

    reactions = post.reaction_count || 0
    boosts = post.boost_count || 0
    replies = post.reply_count || 0

    # 1. Raw engagement (weighted)
    raw_engagement = reactions + boosts * 2 + replies * 1.5

    # 2. Velocity bonus: engagement per hour, capped so a short burst on a
    #    fresh post is a mild boost, not a takeover of the ranking.
    velocity = min(raw_engagement / age_hours, 5.0)
    velocity_factor = 1.0 + :math.log(max(velocity, 1)) / 5.0

    # 3. Underdog bonus: high engagement relative to follower count
    author_followers = Map.get(follower_counts, post.identity_id, 0)

    underdog_factor =
      if author_followers > 0 do
        ratio = raw_engagement / author_followers
        # Cap at 2x bonus for going viral
        1.0 + min(ratio, 1.0)
      else
        # Unknown/new accounts get a slight bonus
        1.2
      end

    # 4. Time decay: gentle — halve about every 24 hours. A short (~6h)
    #    half-life made "trending" behave like "newest": a fresh, barely-engaged
    #    post outranked an older well-engaged one. A longer half-life keeps real
    #    engagement the dominant signal while still favoring recency as a tiebreak.
    decay = :math.exp(-age_hours / 34.6)

    # Final score
    raw_engagement * velocity_factor * underdog_factor * decay
  end

  @impl true
  def home_feed(identity_id, opts) do
    limit = parse_limit(opts)
    window_hours = trending_window()
    cutoff = DateTime.add(DateTime.utc_now(), -window_hours * 3600, :second)
    now = DateTime.utc_now()
    # Resolve the cursor's engagement+id boundary once. Trending
    # orders by engagement, so a `p.id < max_id` UUID compare returns
    # an arbitrary slice and the feed freezes at 20.
    cursor = resolve_cursor(opts)

    # Fetch more candidates than needed to allow diversity filtering
    candidate_limit = limit * @candidate_multiplier

    candidates =
      Post
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.deleted_at))
      |> where([p], not is_nil(p.published_at))
      |> where([p], is_nil(p.parent_id))
      |> where([p], p.inserted_at >= ^cutoff)
      |> where([p], p.reaction_count + p.boost_count + p.reply_count >= 1)
      |> maybe_local(Keyword.get(opts, :local_only, false))
      |> apply_post_cursor(cursor)
      |> Visibility.apply_block_filter(identity_id)
      |> Visibility.apply_mute_filter(identity_id)
      |> Visibility.apply_shadow_ban_filter(identity_id)
      |> Visibility.apply_silence_filter()
      |> order_by([p],
        desc: fragment("? + ? * 2 + ?", p.reaction_count, p.boost_count, p.reply_count),
        desc: p.id
      )
      |> limit(^candidate_limit)
      |> preload([:identity, :quote])
      |> Repo.all()

    # Batch-fetch follower counts for all candidate authors
    author_ids = candidates |> Enum.map(& &1.identity_id) |> Enum.uniq()
    follower_counts = fetch_follower_counts(author_ids)

    context = %{now: now, follower_counts: follower_counts}

    candidates
    |> Enum.map(fn post -> {score_post(post, context), post} end)
    |> Enum.sort_by(fn {score, _} -> score end, :desc)
    |> apply_author_diversity(limit)
  end

  # Scope trending to locally-hosted authors (Explore's Local tab). Uses the
  # `is_local` flag, not an actor-URL prefix, so imported legacy local users
  # (who live at /users/<nick>, not the native /actors/<uuid>) aren't dropped —
  # matching Feeds.maybe_filter_local/2.
  defp maybe_local(query, false), do: query

  defp maybe_local(query, true) do
    from p in query,
      join: i in Identity,
      on: i.id == p.identity_id,
      where: i.is_local == true
  end

  # --- Author diversity ---

  defp apply_author_diversity(scored_posts, limit) do
    {results, _counts} =
      Enum.reduce(scored_posts, {[], %{}}, fn {_score, post}, {acc, counts} ->
        author_count = Map.get(counts, post.identity_id, 0)

        if author_count < @max_per_author and length(acc) < limit do
          {acc ++ [post], Map.put(counts, post.identity_id, author_count + 1)}
        else
          {acc, counts}
        end
      end)

    results
  end

  # --- Follower counts ---

  defp fetch_follower_counts([]), do: %{}

  # Use the Follow schema (not the raw "follows" table) so Ecto can
  # dump the UUID list to Postgres `uuid[]`. With the raw table form
  # the array bind goes in as 36-char strings and Postgrex 0.22 fails
  # with `expected a binary of 16 bytes` from Array.encode.
  defp fetch_follower_counts(identity_ids) do
    from(f in Follow,
      where: f.followee_id in ^identity_ids and f.status == :accepted,
      group_by: f.followee_id,
      select: {f.followee_id, count(f.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # --- Config ---

  defp trending_window do
    case Hybridsocial.Config.get("trending_window_hours") do
      hours when is_integer(hours) and hours > 0 -> hours
      _ -> @default_window_hours
    end
  end

  # --- Private helpers ---

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  # Trending ORDER BY is the engagement expression, so the cursor must
  # be a row-tuple compare on the same expression — not the post id.
  # Look up the boundary post's counts first; when the cursor doesn't
  # resolve (stale client, boost id leaking through, etc.) fall through
  # to no-cursor rather than emitting an empty page.
  defp resolve_cursor(opts) do
    cond do
      max_id = Keyword.get(opts, :max_id) ->
        case lookup_post_cursor(max_id),
          do: (
            nil -> nil
            {eng, id} -> {:older, eng, id}
          )

      min_id = Keyword.get(opts, :min_id) ->
        case lookup_post_cursor(min_id),
          do: (
            nil -> nil
            {eng, id} -> {:newer, eng, id}
          )

      since_id = Keyword.get(opts, :since_id) ->
        case lookup_post_cursor(since_id),
          do: (
            nil -> nil
            {eng, id} -> {:newer, eng, id}
          )

      true ->
        nil
    end
  end

  defp lookup_post_cursor(id) when is_binary(id) do
    Repo.one(
      from p in Post,
        where: p.id == ^id,
        select: {p.reaction_count + p.boost_count * 2 + p.reply_count, p.id}
    )
  end

  defp lookup_post_cursor(_), do: nil

  defp apply_post_cursor(query, nil), do: query

  defp apply_post_cursor(query, {:older, eng, id}) do
    where(
      query,
      [p],
      fragment(
        "(? + ? * 2 + ?, ?) < (?, ?)",
        p.reaction_count,
        p.boost_count,
        p.reply_count,
        p.id,
        ^eng,
        type(^id, Ecto.UUID)
      )
    )
  end

  defp apply_post_cursor(query, {:newer, eng, id}) do
    where(
      query,
      [p],
      fragment(
        "(? + ? * 2 + ?, ?) > (?, ?)",
        p.reaction_count,
        p.boost_count,
        p.reply_count,
        p.id,
        ^eng,
        type(^id, Ecto.UUID)
      )
    )
  end
end

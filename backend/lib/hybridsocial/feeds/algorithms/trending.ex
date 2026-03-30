defmodule Hybridsocial.Feeds.Algorithms.Trending do
  @moduledoc """
  Trending timeline algorithm.

  Returns popular public posts from a configurable time window, scored by
  a multi-factor engagement formula:

  1. **Raw engagement** — reactions + boosts × 2 + replies × 1.5
  2. **Velocity bonus** — engagement concentrated in a short burst scores higher
  3. **Underdog bonus** — posts with high engagement relative to their author's
     follower count get a boost (viral from small accounts)
  4. **Time decay** — exponential decay, halving roughly every 6 hours
  5. **Author diversity** — at most 2 posts per author in the final feed

  The trending window (default 24h) is configurable via the
  `trending_window_hours` admin setting.
  """
  @behaviour Hybridsocial.Feeds.TimelineAlgorithm

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post
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
    age_hours = max(DateTime.diff(now, post.inserted_at, :second) / 3600.0, 0.01)

    reactions = post.reaction_count || 0
    boosts = post.boost_count || 0
    replies = post.reply_count || 0

    # 1. Raw engagement (weighted)
    raw_engagement = reactions + boosts * 2 + replies * 1.5

    # 2. Velocity bonus: engagement per hour (capped at 10x)
    velocity = min(raw_engagement / age_hours, raw_engagement * 10)
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

    # 4. Time decay: halve every ~6 hours
    decay = :math.exp(-age_hours / 8.66)

    # Final score
    raw_engagement * velocity_factor * underdog_factor * decay
  end

  @impl true
  def home_feed(identity_id, opts) do
    limit = parse_limit(opts)
    window_hours = trending_window()
    cutoff = DateTime.add(DateTime.utc_now(), -window_hours * 3600, :second)
    now = DateTime.utc_now()

    # Fetch more candidates than needed to allow diversity filtering
    candidate_limit = limit * @candidate_multiplier

    candidates =
      Post
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.deleted_at))
      |> where([p], is_nil(p.parent_id))
      |> where([p], p.inserted_at >= ^cutoff)
      |> where([p], p.reaction_count + p.boost_count + p.reply_count >= 1)
      |> apply_cursor_filters(opts)
      |> Visibility.apply_block_filter(identity_id)
      |> Visibility.apply_mute_filter(identity_id)
      |> Visibility.apply_shadow_ban_filter(identity_id)
      |> Visibility.apply_silence_filter()
      |> order_by([p],
        desc: fragment("? + ? * 2 + ?", p.reaction_count, p.boost_count, p.reply_count)
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

  defp fetch_follower_counts(identity_ids) do
    from(f in "follows",
      where: f.followee_id in ^identity_ids and f.status == "accepted",
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
end

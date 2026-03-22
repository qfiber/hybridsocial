defmodule Hybridsocial.Feeds.Algorithm do
  @moduledoc """
  Algorithmic feed ("For You") implementation.
  Provides ranked feed based on interaction affinity, engagement velocity,
  content affinity, and freshness.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Feeds.Signals
  alias Hybridsocial.Social.{Post, Follow, Reaction, Boost}

  @default_limit 20
  @max_limit 40
  # Candidate window: last 48 hours
  @candidate_window_hours 48

  @doc """
  Upserts an interaction signal between two identities.
  Increments the interaction count and updates the last_interaction timestamp.
  Optionally merges content tags.
  """
  def record_interaction(identity_id, target_identity_id, tags \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    existing =
      Signals
      |> where([s], s.identity_id == ^identity_id and s.target_identity_id == ^target_identity_id)
      |> Repo.one()

    case existing do
      nil ->
        tag_map = tags_to_map(tags)

        %Signals{}
        |> Signals.changeset(%{
          identity_id: identity_id,
          target_identity_id: target_identity_id,
          interaction_count: 1,
          last_interaction: now,
          content_tags: tag_map
        })
        |> Repo.insert()

      signal ->
        merged_tags = merge_tags(signal.content_tags || %{}, tags)

        signal
        |> Signals.changeset(%{
          interaction_count: signal.interaction_count + 1,
          last_interaction: now,
          content_tags: merged_tags
        })
        |> Repo.update()
    end
  end

  @doc """
  Returns an algorithmically ranked feed for the given identity.
  For MVP, uses simplified scoring: affinity + engagement + freshness.

  ## Options
    * `:limit`  - max number of posts (default 20, max 40)
    * `:max_id` - cursor for pagination (older)
    * `:min_id` - cursor for pagination (newer)
  """
  def algorithmic_timeline(identity_id, opts \\ []) do
    limit = parse_limit(opts)
    cutoff = DateTime.add(DateTime.utc_now(), -@candidate_window_hours * 3600, :second)

    # Get followed account IDs
    followed_ids =
      Follow
      |> where([f], f.follower_id == ^identity_id and f.status == :accepted)
      |> select([f], f.followee_id)
      |> Repo.all()

    # Get interaction signals for scoring
    signals =
      Signals
      |> where([s], s.identity_id == ^identity_id)
      |> Repo.all()
      |> Map.new(fn s -> {s.target_identity_id, s} end)

    # Get candidate posts: from followed accounts + popular public posts
    followed_posts =
      Post
      |> where([p], p.identity_id in ^followed_ids)
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.inserted_at >= ^cutoff)
      |> maybe_max_id(Keyword.get(opts, :max_id))
      |> maybe_min_id(Keyword.get(opts, :min_id))
      |> preload(:identity)
      |> Repo.all()

    popular_posts =
      Post
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.inserted_at >= ^cutoff)
      |> where([p], p.identity_id not in ^followed_ids)
      |> where([p], p.reaction_count >= 1 or p.boost_count >= 1)
      |> maybe_max_id(Keyword.get(opts, :max_id))
      |> maybe_min_id(Keyword.get(opts, :min_id))
      |> preload(:identity)
      |> Repo.all()

    # Combine, deduplicate, score, and sort
    all_posts =
      (followed_posts ++ popular_posts)
      |> Enum.uniq_by(& &1.id)

    now = DateTime.utc_now()

    scored_posts =
      all_posts
      |> Enum.map(fn post ->
        score = compute_score(post, signals, now)
        {score, post}
      end)
      |> Enum.sort_by(fn {score, _} -> score end, :desc)
      |> Enum.take(limit)
      |> Enum.map(fn {_score, post} -> post end)

    scored_posts
  end

  @doc """
  Precomputes interaction signals from recent activity.
  Scans recent reactions and boosts to build/update the signals table.
  """
  def precompute_signals do
    cutoff = DateTime.add(DateTime.utc_now(), -7 * 24 * 3600, :second)

    # Get recent reactions
    reactions =
      Reaction
      |> where([r], r.inserted_at >= ^cutoff)
      |> join(:inner, [r], p in Post, on: r.post_id == p.id)
      |> select([r, p], %{identity_id: r.identity_id, target_identity_id: p.identity_id})
      |> Repo.all()

    # Get recent boosts
    boosts =
      Boost
      |> where([b], b.inserted_at >= ^cutoff and is_nil(b.deleted_at))
      |> join(:inner, [b], p in Post, on: b.post_id == p.id)
      |> select([b, p], %{identity_id: b.identity_id, target_identity_id: p.identity_id})
      |> Repo.all()

    interactions = reactions ++ boosts

    # Group by identity pair and upsert
    interactions
    |> Enum.filter(fn %{identity_id: id, target_identity_id: tid} -> id != tid end)
    |> Enum.group_by(fn %{identity_id: id, target_identity_id: tid} -> {id, tid} end)
    |> Enum.each(fn {{identity_id, target_id}, items} ->
      count = length(items)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      %Signals{}
      |> Signals.changeset(%{
        identity_id: identity_id,
        target_identity_id: target_id,
        interaction_count: count,
        last_interaction: now
      })
      |> Repo.insert(
        on_conflict: [set: [interaction_count: count, last_interaction: now, updated_at: now]],
        conflict_target: [:identity_id, :target_identity_id]
      )
    end)

    :ok
  end

  # --- Private ---

  defp compute_score(post, signals, now) do
    # Affinity (40%): interaction count with author
    affinity =
      case Map.get(signals, post.identity_id) do
        nil -> 0.0
        signal -> min(signal.interaction_count / 10.0, 1.0) * 0.4
      end

    # Engagement (20%): reactions + boosts normalized
    engagement = min((post.reaction_count + post.boost_count) / 20.0, 1.0) * 0.2

    # Freshness (10%): exponential decay over 48 hours
    age_hours = DateTime.diff(now, post.inserted_at, :second) / 3600.0
    freshness = :math.exp(-age_hours / 24.0) * 0.1

    affinity + engagement + freshness
  end

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp maybe_max_id(query, nil), do: query
  defp maybe_max_id(query, max_id), do: where(query, [p], p.id < ^max_id)

  defp maybe_min_id(query, nil), do: query
  defp maybe_min_id(query, min_id), do: where(query, [p], p.id > ^min_id)

  defp tags_to_map(tags) when is_list(tags) do
    tags
    |> Enum.frequencies()
    |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
  end

  defp merge_tags(existing, new_tags) when is_list(new_tags) do
    new_map = tags_to_map(new_tags)

    Map.merge(existing, new_map, fn _k, v1, v2 ->
      (v1 || 0) + (v2 || 0)
    end)
  end
end

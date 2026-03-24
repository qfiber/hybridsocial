defmodule Hybridsocial.Feeds.Algorithms.Trending do
  @moduledoc """
  Trending timeline algorithm.

  Returns popular public posts from the last 24 hours, sorted by engagement
  score with time decay. Unlike the chronological and algorithmic feeds, this
  algorithm does not filter by followed accounts -- it surfaces globally
  trending content.
  """
  @behaviour Hybridsocial.Feeds.TimelineAlgorithm

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post
  alias Hybridsocial.Feeds.Visibility

  @default_limit 20
  @max_limit 40
  @trending_window_hours 24

  @impl true
  def name, do: "trending"

  @impl true
  def score_post(post, context) do
    now = Map.get(context, :now, DateTime.utc_now())
    age_hours = DateTime.diff(now, post.inserted_at, :second) / 3600.0

    # Engagement: reactions + boosts weighted 2x
    raw_engagement = (post.reaction_count || 0) + (post.boost_count || 0) * 2

    # Time decay: halve the score every 6 hours
    decay = :math.exp(-age_hours / 8.66)

    raw_engagement * decay
  end

  @impl true
  def home_feed(identity_id, opts) do
    limit = parse_limit(opts)
    cutoff = DateTime.add(DateTime.utc_now(), -@trending_window_hours * 3600, :second)
    now = DateTime.utc_now()

    candidates =
      Post
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.inserted_at >= ^cutoff)
      |> where([p], p.reaction_count + p.boost_count >= 1)
      |> apply_cursor_filters(opts)
      |> Visibility.apply_block_filter(identity_id)
      |> Visibility.apply_mute_filter(identity_id)
      |> preload(:identity)
      |> Repo.all()

    context = %{now: now}

    candidates
    |> Enum.map(fn post -> {score_post(post, context), post} end)
    |> Enum.sort_by(fn {score, _} -> score end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_score, post} -> post end)
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

defmodule Hybridsocial.Feeds.Algorithms.Algorithmic do
  @moduledoc """
  Algorithmic ("For You") timeline algorithm.

  Wraps the existing `Hybridsocial.Feeds.Algorithm` module to provide ranked
  feeds based on interaction affinity, engagement velocity, and freshness.
  """
  @behaviour Hybridsocial.Feeds.TimelineAlgorithm

  alias Hybridsocial.Feeds.Algorithm

  @impl true
  def name, do: "algorithmic"

  @impl true
  def home_feed(identity_id, opts) do
    Algorithm.algorithmic_timeline(identity_id, opts)
  end

  @impl true
  def score_post(post, context) do
    signals = Map.get(context, :signals, %{})
    now = Map.get(context, :now, DateTime.utc_now())

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
end

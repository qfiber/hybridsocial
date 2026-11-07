defmodule Hybridsocial.Feeds.Algorithms.Trending do
  @moduledoc """
  Trending timeline algorithm: Home's Top tab and the `sort=trending` order of
  the public and global timelines.

  It reads Explore's precomputed Trending feed (`Trending.ExploreFeed`) rather
  than ranking on each request. A ranking computed on read shifts between
  requests, and the clients page by the last post's id, so pages repeated and
  skipped posts (#221). The stored feed keeps one order between refreshes, caps
  repeat authors across the whole feed, and applies moderation and the viewer's
  filters on read.

  The ranking and its `explore_trending_*` tunables live in `ExploreFeed`.
  """
  @behaviour Hybridsocial.Feeds.TimelineAlgorithm

  alias Hybridsocial.Trending.ExploreFeed

  @impl true
  def name, do: "trending"

  # Posts are ranked when the feed is precomputed, not per request.
  @impl true
  def score_post(_post, _context), do: 0.0

  @impl true
  def home_feed(identity_id, opts) do
    # A ranked feed has no "newer than" side: posts don't arrive at the top of
    # it, so a `min_id`/`since_id` poll gets nothing rather than a re-ranking.
    if Keyword.get(opts, :min_id) || Keyword.get(opts, :since_id) do
      []
    else
      [
        viewer_id: identity_id,
        local_only: Keyword.get(opts, :local_only, false),
        max_id: Keyword.get(opts, :max_id),
        limit: Keyword.get(opts, :limit, 20)
      ]
      |> ExploreFeed.list()
      |> Enum.map(&elem(&1, 0))
    end
  end
end

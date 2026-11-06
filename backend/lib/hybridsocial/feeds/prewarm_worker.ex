defmodule Hybridsocial.Feeds.PrewarmWorker do
  @moduledoc """
  Keeps the expensive read feeds warm so visitors never pay the cold
  query + serialization cost on the request path.

  Every cycle it refreshes:

    * the global timeline snapshot (with and without replies), and
    * the top trending hashtag timelines.

  Long-tail hashtags that aren't trending are not prewarmed — there are
  unboundedly many — but they still get a lazy snapshot on first view via
  `Hybridsocial.Feeds.Snapshot.fetch/2`, so only the very first visitor
  eats the cost.

  Mirrors the GenServer-timer pattern used by `Hybridsocial.Trending.Worker`.
  """

  use GenServer
  require Logger

  alias Hybridsocial.Feeds
  alias Hybridsocial.Feeds.Snapshot
  alias Hybridsocial.Trending
  alias HybridsocialWeb.Serializers.PostSerializer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Warm immediately on boot so the first visitor after a deploy /
    # restart doesn't hit a cold cache.
    send(self(), :refresh)
    {:ok, %{interval: Keyword.get(opts, :interval)}}
  end

  @impl true
  def handle_info(:refresh, state) do
    if Snapshot.enabled?() do
      refresh_global()
      refresh_trending_tags()
    end

    schedule_next(state)
    {:noreply, state}
  end

  defp refresh_global do
    for include_replies <- [false, true] do
      safe("global(include_replies=#{include_replies})", fn ->
        Snapshot.refresh(Snapshot.global_key(include_replies), fn ->
          [viewer_id: nil, include_replies: include_replies, include_locked: true]
          |> Feeds.global_timeline()
          |> PostSerializer.serialize_many(current_identity_id: nil)
        end)
      end)
    end
  end

  defp refresh_trending_tags do
    for tag <- trending_tags() do
      safe("tag(#{tag})", fn ->
        Snapshot.refresh(Snapshot.hashtag_key(tag), fn ->
          tag
          |> Feeds.hashtag_timeline(viewer_id: nil, include_locked: true)
          |> PostSerializer.serialize_many(current_identity_id: nil)
        end)
      end)
    end
  end

  defp trending_tags do
    count = Snapshot.trending_tag_count()

    if count > 0 do
      Trending.get_trending_hashtags(limit: count)
      # Trending stores the canonical (lowercase) tag slug in target_id.
      |> Enum.map(& &1.target_id)
      |> Enum.reject(&(&1 in [nil, ""]))
    else
      []
    end
  rescue
    e ->
      Logger.error("PrewarmWorker: failed to load trending tags: #{inspect(e)}")
      []
  end

  # Isolate each feed's refresh so one failure (a bad post, a query
  # error) doesn't abort the rest of the cycle or crash the worker.
  defp safe(label, fun) do
    fun.()
    :ok
  rescue
    e -> Logger.error("PrewarmWorker: refreshing #{label} failed: #{inspect(e)}")
  end

  defp schedule_next(state) do
    interval_ms = (state[:interval] || Snapshot.interval_seconds()) * 1000
    Process.send_after(self(), :refresh, interval_ms)
  end
end

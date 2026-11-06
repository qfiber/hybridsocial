defmodule Hybridsocial.Trending.Worker do
  @moduledoc """
  GenServer that periodically recomputes trending data, including Explore's
  Trending feed. Runs every `explore_trending_refresh_seconds` (default 5
  minutes). Does not start in test environment.
  """
  use GenServer

  require Logger

  alias Hybridsocial.Config
  alias Hybridsocial.Trending.ExploreFeed

  @default_interval_seconds 300
  # Soon after boot rather than a full interval later, so a fresh deploy doesn't
  # show an empty Trending tab for five minutes.
  @first_run_delay :timer.seconds(30)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :compute, @first_run_delay)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:compute, state) do
    # One rescue per step: a failure in one must not silently stop the others.
    run("trending posts", &Hybridsocial.Trending.compute_trending_posts/0)
    run("trending hashtags", &Hybridsocial.Trending.compute_trending_hashtags/0)
    run("explore feed", &ExploreFeed.refresh/0)
    run("trending cleanup", &Hybridsocial.Trending.cleanup_old_trending/0)
    run("export cleanup", &Hybridsocial.Portability.cleanup_expired_exports/0)

    Process.send_after(self(), :compute, interval())
    {:noreply, state}
  end

  defp run(label, fun) do
    fun.()
  rescue
    e -> Logger.error("Trending #{label} failed: #{inspect(e)}")
  end

  # Settings are stored untyped, so a stored string is possible. Anything
  # unusable falls back to the default rather than crash-looping the worker.
  defp interval do
    seconds =
      case Config.get("explore_trending_refresh_seconds", @default_interval_seconds) do
        n when is_number(n) and n > 0 ->
          n

        s when is_binary(s) ->
          case Integer.parse(s) do
            {n, _} when n > 0 -> n
            _ -> @default_interval_seconds
          end

        _ ->
          @default_interval_seconds
      end

    trunc(seconds * 1000)
  end
end

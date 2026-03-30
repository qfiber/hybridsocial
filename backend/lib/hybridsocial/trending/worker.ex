defmodule Hybridsocial.Trending.Worker do
  @moduledoc """
  GenServer that periodically recomputes trending data.
  Runs every 5 minutes (configurable). Does not start in test environment.
  """
  use GenServer

  require Logger

  @default_interval :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    schedule_next(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:compute, state) do
    try do
      Hybridsocial.Trending.compute_trending_posts()
      Hybridsocial.Trending.compute_trending_hashtags()
      Hybridsocial.Trending.cleanup_old_trending()
      Hybridsocial.Portability.cleanup_expired_exports()
    rescue
      e ->
        Logger.error("Trending computation failed: #{inspect(e)}")
    end

    schedule_next(state.interval)
    {:noreply, state}
  end

  defp schedule_next(interval) do
    Process.send_after(self(), :compute, interval)
  end
end

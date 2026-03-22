defmodule Hybridsocial.Feeds.SignalWorker do
  @moduledoc """
  GenServer that periodically precomputes user interaction signals
  for the algorithmic feed. Runs every 10 minutes.
  """
  use GenServer

  require Logger

  @interval_ms :timer.minutes(10)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_work()
    {:ok, state}
  end

  @impl true
  def handle_info(:precompute, state) do
    Logger.info("SignalWorker: precomputing interaction signals")

    try do
      Hybridsocial.Feeds.Algorithm.precompute_signals()
    rescue
      e ->
        Logger.error("SignalWorker: error precomputing signals: #{inspect(e)}")
    end

    schedule_work()
    {:noreply, state}
  end

  defp schedule_work do
    Process.send_after(self(), :precompute, @interval_ms)
  end
end

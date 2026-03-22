defmodule Hybridsocial.Federation.DeliveryWorker do
  @moduledoc """
  GenServer for processing the federation delivery queue.
  Periodically checks for pending and failed deliveries, and processes them.
  In the future this will be replaced with NATS-based delivery.
  """

  use GenServer

  require Logger

  alias Hybridsocial.Federation.Publisher

  @retry_interval :timer.minutes(5)

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- Server callbacks ---

  @impl true
  def init(_opts) do
    # Schedule the first retry check after a short delay to let the app boot
    schedule_retry_check(5_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:retry_failed, state) do
    try do
      Publisher.retry_failed_deliveries()
    rescue
      e ->
        Logger.error("Error retrying failed deliveries: #{inspect(e)}")
    end

    schedule_retry_check(@retry_interval)
    {:noreply, state}
  end

  # --- Private helpers ---

  defp schedule_retry_check(interval) do
    Process.send_after(self(), :retry_failed, interval)
  end
end

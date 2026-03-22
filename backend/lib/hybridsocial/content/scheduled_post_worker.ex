defmodule Hybridsocial.Content.ScheduledPostWorker do
  @moduledoc """
  GenServer that periodically publishes due scheduled posts.
  Runs every minute. Not started in test environment.
  """
  use GenServer

  alias Hybridsocial.Content.ScheduledPosts

  @interval :timer.minutes(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    ScheduledPosts.publish_due_posts()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @interval)
  end
end

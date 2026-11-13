defmodule Hybridsocial.Social.PostExpiryWorker do
  @moduledoc """
  Deletes timed posts once their `expires_at` passes (#261).

  Ticks every `post_expiry_sweep_seconds` (default 60), so a post outlives
  its timer by at most about that long. Deletion goes through
  `Posts.delete_post/2`, the same path as a manual delete, so remote
  servers get a federated `Delete`. Each run is capped by
  `post_expiry_batch_size` to spread a backlog over several ticks.
  """
  use GenServer

  alias Hybridsocial.Config
  alias Hybridsocial.Social.Posts

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    case safely_delete() do
      n when n > 0 -> Logger.info("PostExpiryWorker: deleted #{n} expired posts")
      _ -> :ok
    end

    schedule_tick()
    {:noreply, state}
  end

  defp safely_delete do
    Posts.delete_expired_posts(DateTime.utc_now(), setting("post_expiry_batch_size", 500))
  rescue
    e ->
      Logger.error("PostExpiryWorker crashed: #{Exception.message(e)}")
      0
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, :timer.seconds(setting("post_expiry_sweep_seconds", 60)))
  end

  defp setting(key, default) do
    case Config.get(key, default) do
      n when is_integer(n) and n > 0 ->
        n

      n when is_binary(n) ->
        case Integer.parse(n) do
          {int, ""} when int > 0 -> int
          _ -> default
        end

      _ ->
        default
    end
  end
end

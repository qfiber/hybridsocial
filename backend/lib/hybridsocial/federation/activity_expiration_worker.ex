defmodule Hybridsocial.Federation.ActivityExpirationWorker do
  @moduledoc """
  GenServer that periodically expires promotions and ads.

  Runs every hour.
  """
  use GenServer

  require Logger

  @check_interval :timer.hours(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_expired, state) do
    delete_expired_activities()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_expired, @check_interval)
  end

  # Timed posts (`posts.expires_at`) are deleted by
  # `Social.PostExpiryWorker`, which goes through `Posts.delete_post/2` so
  # the federated Delete and reply-count bookkeeping happen.
  defp delete_expired_activities do
    case Hybridsocial.Promotions.expire_promotions() do
      {:ok, promo_count} when promo_count > 0 ->
        Logger.info("ActivityExpirationWorker: expired #{promo_count} promotions")

      _ ->
        :ok
    end

    case Hybridsocial.Ads.expire_ads() do
      {:ok, ad_count} when ad_count > 0 ->
        Logger.info("ActivityExpirationWorker: expired #{ad_count} ads")

      _ ->
        :ok
    end
  end
end

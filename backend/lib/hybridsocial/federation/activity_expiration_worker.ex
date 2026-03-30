defmodule Hybridsocial.Federation.ActivityExpirationWorker do
  @moduledoc """
  GenServer that periodically deletes expired activities/posts.

  Runs every hour and soft-deletes any posts whose `expires_at` has passed.
  """
  use GenServer

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post

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

  defp delete_expired_activities do
    now = DateTime.utc_now()

    {count, _} =
      Post
      |> where([p], not is_nil(p.expires_at) and p.expires_at < ^now and is_nil(p.deleted_at))
      |> Repo.update_all(set: [deleted_at: now])

    if count > 0 do
      Logger.info("ActivityExpirationWorker: soft-deleted #{count} expired posts")
    end

    # Also expire promotions
    case Hybridsocial.Promotions.expire_promotions() do
      {:ok, promo_count} when promo_count > 0 ->
        Logger.info("ActivityExpirationWorker: expired #{promo_count} promotions")
      _ -> :ok
    end

    # Also expire ads
    case Hybridsocial.Ads.expire_ads() do
      {:ok, ad_count} when ad_count > 0 ->
        Logger.info("ActivityExpirationWorker: expired #{ad_count} ads")
      _ -> :ok
    end
  end
end

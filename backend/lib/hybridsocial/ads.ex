defmodule Hybridsocial.Ads do
  @moduledoc "Ad management — create, serve, track impressions and clicks."

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Ads.Ad

  def enabled? do
    Hybridsocial.Config.get("ads_enabled", false)
  end

  # --- Public: Serve ads ---

  @doc "Get active ads for a placement."
  def get_ads(placement, opts \\ []) do
    now = DateTime.utc_now()
    limit = Keyword.get(opts, :limit, 3)

    Ad
    |> where([a], a.is_active == true and a.placement == ^placement)
    |> where([a], is_nil(a.starts_at) or a.starts_at <= ^now)
    |> where([a], is_nil(a.expires_at) or a.expires_at > ^now)
    |> order_by([a], desc: a.priority)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Record an impression."
  def record_impression(ad_id) do
    Ad
    |> where([a], a.id == ^ad_id)
    |> Repo.update_all(inc: [impressions: 1])
  end

  @doc "Record a click."
  def record_click(ad_id) do
    Ad
    |> where([a], a.id == ^ad_id)
    |> Repo.update_all(inc: [clicks: 1])
  end

  # --- Admin: CRUD ---

  def list_ads(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    placement = Keyword.get(opts, :placement)

    query =
      Ad
      |> order_by([a], desc: a.inserted_at)
      |> limit(^limit)

    query = if placement, do: where(query, [a], a.placement == ^placement), else: query

    Repo.all(query)
  end

  def get_ad(id), do: Repo.get(Ad, id)

  def create_ad(attrs) do
    %Ad{}
    |> Ad.changeset(attrs)
    |> Repo.insert()
  end

  def update_ad(id, attrs) do
    case get_ad(id) do
      nil -> {:error, :not_found}
      ad -> ad |> Ad.changeset(attrs) |> Repo.update()
    end
  end

  def delete_ad(id) do
    case get_ad(id) do
      nil -> {:error, :not_found}
      ad -> Repo.delete(ad)
    end
  end

  def toggle_ad(id) do
    case get_ad(id) do
      nil -> {:error, :not_found}
      ad -> ad |> Ecto.Changeset.change(is_active: !ad.is_active) |> Repo.update()
    end
  end

  @doc "Expire ads past their expiry."
  def expire_ads do
    now = DateTime.utc_now()
    {count, _} =
      Ad
      |> where([a], a.is_active == true and not is_nil(a.expires_at) and a.expires_at <= ^now)
      |> Repo.update_all(set: [is_active: false])
    {:ok, count}
  end
end

defmodule HybridsocialWeb.Api.V1.AdController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Ads

  def index(conn, params) do
    if not Ads.enabled?() do
      json(conn, [])
    else
      placement = params["placement"] || "sidebar"
      ads = Ads.get_ads(placement)

      # Record impressions
      for ad <- ads, do: Ads.record_impression(ad.id)

      json(conn, Enum.map(ads, &serialize_ad/1))
    end
  end

  def click(conn, %{"id" => id}) do
    Ads.record_click(id)
    json(conn, %{status: "ok"})
  end

  defp serialize_ad(ad) do
    %{
      id: ad.id,
      title: ad.title,
      description: ad.description,
      image_url: ad.image_url,
      link_url: ad.link_url,
      placement: ad.placement
    }
  end
end

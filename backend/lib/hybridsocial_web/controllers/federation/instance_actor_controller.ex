defmodule HybridsocialWeb.Federation.InstanceActorController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Federation.InstanceActor

  def show(conn, _params) do
    if InstanceActor.keys_configured?() do
      conn
      |> put_resp_content_type("application/activity+json")
      |> json(InstanceActor.to_ap())
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Instance actor not configured"})
    end
  end
end

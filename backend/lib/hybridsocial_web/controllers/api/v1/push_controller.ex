defmodule HybridsocialWeb.Api.V1.PushController do
  use HybridsocialWeb, :controller
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Push.Subscription

  # POST /api/v1/push/subscription
  def create(conn, %{"subscription" => sub_params}) do
    identity = conn.assigns.current_identity

    attrs = %{
      identity_id: identity.id,
      endpoint: sub_params["endpoint"],
      key_p256dh: get_in(sub_params, ["keys", "p256dh"]),
      key_auth: get_in(sub_params, ["keys", "auth"]),
      user_agent: List.first(Plug.Conn.get_req_header(conn, "user-agent"))
    }

    case %Subscription{}
         |> Subscription.changeset(attrs)
         |> Repo.insert(
           on_conflict: {:replace, [:key_p256dh, :key_auth, :user_agent, :updated_at]},
           conflict_target: [:identity_id, :endpoint]
         ) do
      {:ok, sub} ->
        conn |> put_status(:created) |> json(%{id: sub.id, endpoint: sub.endpoint})

      {:error, _changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid subscription"})
    end
  end

  # GET /api/v1/push/subscription
  def show(conn, _params) do
    identity = conn.assigns.current_identity
    subs = Repo.all(from s in Subscription, where: s.identity_id == ^identity.id)
    json(conn, Enum.map(subs, fn s -> %{id: s.id, endpoint: s.endpoint} end))
  end

  # DELETE /api/v1/push/subscription
  def delete(conn, %{"endpoint" => endpoint}) do
    identity = conn.assigns.current_identity

    from(s in Subscription,
      where: s.identity_id == ^identity.id and s.endpoint == ^endpoint
    )
    |> Repo.delete_all()

    json(conn, %{ok: true})
  end

  # GET /api/v1/push/vapid_key
  def vapid_key(conn, _params) do
    json(conn, %{public_key: Hybridsocial.Push.Vapid.public_key()})
  end
end

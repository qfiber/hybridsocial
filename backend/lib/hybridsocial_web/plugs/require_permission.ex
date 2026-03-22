defmodule HybridsocialWeb.Plugs.RequirePermission do
  @moduledoc """
  Plug that checks if the current user has a specific permission.

  Usage in a router pipeline:
      plug RequirePermission, permission: "reports.view"
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Hybridsocial.Auth.RBAC

  def init(opts), do: opts

  def call(conn, permission: permission) do
    case conn.assigns[:current_identity] do
      %{id: identity_id} ->
        if RBAC.has_permission?(identity_id, permission) do
          conn
        else
          Hybridsocial.Moderation.log(identity_id, "auth.permission_denied", nil, nil, %{
            required: permission,
            path: conn.request_path
          })

          conn
          |> put_status(:forbidden)
          |> json(%{error: "permission.denied", required: permission})
          |> halt()
        end

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "permission.denied", required: permission})
        |> halt()
    end
  end
end

defmodule HybridsocialWeb.Plugs.RequireAdmin do
  @moduledoc """
  Plug that checks if the current user has any staff role.
  Kept for backwards compatibility — the admin pipeline uses this
  to gate access to the admin panel. Per-action permission checks
  are handled by RequirePermission or inline checks.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Hybridsocial.Auth.RBAC

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_identity] do
      %{id: identity_id} ->
        if RBAC.staff?(identity_id) do
          conn
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "auth.forbidden", message: "Admin access required"})
          |> halt()
        end

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "auth.forbidden", message: "Admin access required"})
        |> halt()
    end
  end
end

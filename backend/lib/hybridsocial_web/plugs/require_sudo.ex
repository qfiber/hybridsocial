defmodule HybridsocialWeb.Plugs.RequireSudo do
  @moduledoc """
  Step-up auth gate for the admin panel. Requires a valid sudo window
  on the caller's access token — granted by re-entering password +
  TOTP via POST /api/v1/admin/sudo. A successful check extends the
  window (rolling TTL), so active admin sessions stay unlocked but an
  idle tab times out after `Hybridsocial.Auth.sudo_ttl_seconds/0`.

  Requests sent from a timer rather than by the operator set
  `x-sudo-passive: 1`, which checks the window without extending it. Otherwise
  an open tab's polling would keep the window alive forever. The header can
  only ever give a client less than the default, so it needs no verification.

  Every allowed response carries `x-sudo-expires-at`, so the client can track
  the real expiry instead of guessing at the rolling window.

  Must run after `Auth` + `RequireAuth`.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Hybridsocial.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_token] do
      nil ->
        deny(conn)

      token ->
        case check(conn, token) do
          {:ok, until} -> put_resp_header(conn, "x-sudo-expires-at", DateTime.to_iso8601(until))
          {:error, :sudo_required} -> deny(conn)
        end
    end
  end

  defp check(conn, token) do
    if get_req_header(conn, "x-sudo-passive") == ["1"] do
      Auth.check_sudo(token)
    else
      Auth.check_and_extend_sudo(token)
    end
  end

  defp deny(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: "auth.sudo_required",
      message: "Please re-enter your password and 2FA code to access the admin panel."
    })
    |> halt()
  end
end

defmodule HybridsocialWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Plug that adds security headers to all responses.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-xss-protection", "0")
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("permissions-policy", "camera=(), microphone=(), geolocation=()")
    |> put_resp_header("content-security-policy", build_csp())
    |> put_resp_header("strict-transport-security", "max-age=31536000; includeSubDomains")
  end

  defp build_csp do
    # CSP for API-only backend — restrictive
    [
      "default-src 'none'",
      "frame-ancestors 'none'",
      "base-uri 'none'",
      "form-action 'self'"
    ]
    |> Enum.join("; ")
  end
end

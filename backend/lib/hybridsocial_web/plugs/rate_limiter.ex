defmodule HybridsocialWeb.Plugs.RateLimiter do
  @moduledoc """
  Valkey-backed rate limiter.

  Authenticated users: 300 requests/minute (configurable).
  Anonymous users: 60 requests/minute (configurable).

  Returns 429 Too Many Requests with Retry-After header when exceeded.
  Falls back to allowing requests if Valkey is unavailable (fail-open).
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Hybridsocial.Cache

  def init(opts), do: opts

  def call(conn, _opts) do
    if enabled?() do
      identifier = rate_limit_identifier(conn)
      limit = rate_limit(conn)
      window = current_window()

      case check_rate(identifier, window, limit) do
        :ok ->
          conn

        {:error, retry_after} ->
          conn
          |> put_resp_header("retry-after", Integer.to_string(retry_after))
          |> put_status(:too_many_requests)
          |> json(%{error: "rate_limit.exceeded", message: "Rate limit exceeded. Try again later."})
          |> halt()
      end
    else
      conn
    end
  end

  defp enabled? do
    Application.get_env(:hybridsocial, :rate_limiting_enabled, true)
  end

  defp rate_limit_identifier(conn) do
    case conn.assigns[:current_identity] do
      nil ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()
        "ip:#{ip}"

      identity ->
        "identity:#{identity.id}"
    end
  end

  defp rate_limit(conn) do
    case conn.assigns[:current_identity] do
      nil -> Hybridsocial.Config.rate_limit_anonymous()
      _ -> Hybridsocial.Config.rate_limit_authenticated()
    end
  end

  defp current_window do
    div(System.system_time(:second), 60)
  end

  defp check_rate(identifier, window, limit) do
    key = "ratelimit:#{identifier}:#{window}"

    case Cache.increment(key, 120) do
      {:ok, count} when count > limit ->
        retry_after = 60 - rem(System.system_time(:second), 60)
        {:error, max(retry_after, 1)}

      {:ok, _count} ->
        :ok

      {:error, _} ->
        # Fail-open: if Valkey is down, allow the request
        :ok
    end
  end
end

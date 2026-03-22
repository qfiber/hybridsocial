defmodule HybridsocialWeb.Plugs.RateLimiter do
  @moduledoc """
  Valkey-backed rate limiter.

  Sensitive endpoints (auth, 2FA) have stricter per-endpoint limits.
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
      {limit, window_seconds} = get_limit(conn)
      window = current_window(window_seconds)

      case check_rate(identifier, conn.request_path, window, window_seconds, limit) do
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

  defp authenticated?(conn) do
    conn.assigns[:current_identity] != nil
  end

  defp get_limit(conn) do
    case conn.request_path do
      "/api/v1/auth/password/reset" -> {5, 3600}
      "/api/v1/auth/password/change" -> {5, 3600}
      "/api/v1/auth/2fa/verify" -> {5, 900}
      "/api/v1/auth/2fa/login" -> {5, 900}
      "/api/v1/auth/login" -> {10, 900}
      "/api/v1/auth/register" -> {5, 3600}
      _ ->
        if authenticated?(conn) do
          {Hybridsocial.Config.rate_limit_authenticated(), 60}
        else
          {Hybridsocial.Config.rate_limit_anonymous(), 60}
        end
    end
  end

  defp current_window(window_seconds) do
    div(System.system_time(:second), window_seconds)
  end

  defp check_rate(identifier, path, window, window_seconds, limit) do
    key = rate_key(identifier, path, window)

    case Cache.increment(key, window_seconds + 60) do
      {:ok, count} when count > limit ->
        retry_after = window_seconds - rem(System.system_time(:second), window_seconds)
        {:error, max(retry_after, 1)}

      {:ok, _count} ->
        :ok

      {:error, _} ->
        # Fail-open: if Valkey is down, allow the request
        :ok
    end
  end

  defp rate_key(identifier, path, window) do
    case path do
      "/api/v1/auth/" <> _ -> "ratelimit:auth:#{identifier}:#{path}:#{window}"
      _ -> "ratelimit:#{identifier}:#{window}"
    end
  end
end

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
          |> json(%{
            error: "rate_limit.exceeded",
            message: "Rate limit exceeded. Try again later."
          })
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
    alias Hybridsocial.Config

    case conn.request_path do
      path when path in ["/api/v1/auth/password/reset", "/api/v1/auth/password/change"] ->
        {Config.get("rate_limit_password_reset", 5), 3600}

      path when path in ["/api/v1/auth/2fa/verify", "/api/v1/auth/2fa/login"] ->
        {Config.get("rate_limit_2fa", 5), 900}

      "/api/v1/auth/login" ->
        {Config.get("rate_limit_login", 10), 900}

      "/api/v1/auth/register" ->
        {Config.get("rate_limit_register", 20), 3600}

      "/api/v1/auth/resend_confirmation" ->
        {Config.get("rate_limit_resend_confirmation", 2), 3600}

      path when path in ["/api/v1/auth/recover/validate", "/api/v1/auth/recover/complete"] ->
        {Config.get("rate_limit_recover", 5), 3600}

      # OAuth app registration is unauthenticated by necessity (a client has
      # no user yet), so it gets its own per-IP ceiling instead of sharing the
      # anonymous browsing bucket. Only the POST — listing your own apps is a
      # normal authenticated read.
      path when path in ["/api/v1/apps", "/api/v1/apps/"] and conn.method == "POST" ->
        {Config.get("rate_limit_app_registration", 10), 3600}

      "/oauth/token" ->
        {Config.get("rate_limit_oauth_token", 30), 900}

      # Every remote avatar, emoji and image in a feed is one proxy request
      # with no auth header, so in the shared per-IP bucket a few screens of
      # scrolling hit 429 and images went missing. URLs are signed, so only
      # media we emitted can be requested.
      "/proxy/" <> _ ->
        {Config.get("rate_limit_media_proxy", 3000), 60}

      _ ->
        if authenticated?(conn) do
          {Config.rate_limit_authenticated(), 60}
        else
          {Config.rate_limit_anonymous(), 60}
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

  # Endpoints with a bespoke limit need a bespoke counter too — sharing the
  # generic per-minute bucket would compare a 10/hour ceiling against a count
  # accumulated from every other request the caller made.
  defp rate_key(identifier, path, window) do
    case path do
      "/api/v1/auth/" <> _ -> "ratelimit:auth:#{identifier}:#{path}:#{window}"
      "/api/v1/apps" <> _ -> "ratelimit:oauth:#{identifier}:#{path}:#{window}"
      "/oauth/" <> _ -> "ratelimit:oauth:#{identifier}:#{path}:#{window}"
      "/proxy/" <> _ -> "ratelimit:proxy:#{identifier}:#{window}"
      _ -> "ratelimit:#{identifier}:#{window}"
    end
  end
end

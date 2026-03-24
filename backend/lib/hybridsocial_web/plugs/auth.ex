defmodule HybridsocialWeb.Plugs.Auth do
  @moduledoc """
  Plug that authenticates requests via Bearer token.
  Sets `conn.assigns.current_identity` on success.
  Uses Valkey cache to avoid DB lookup on every request.
  """
  import Plug.Conn
  alias Hybridsocial.Auth.Token
  alias Hybridsocial.Accounts
  alias Hybridsocial.Cache.TokenCache

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = Plug.Conn.fetch_cookies(conn)

    with {:ok, token} <- extract_token(conn),
         {:ok, claims} <- Token.verify_access_token(token),
         identity when not is_nil(identity) <- fetch_identity(claims["sub"]) do
      # Update last activity (async, throttled via cache)
      token_hash = Token.hash_token(token)
      maybe_touch_session(token_hash, conn)

      conn
      |> assign(:current_identity, identity)
      |> assign(:current_token, token)
    else
      _ ->
        conn
    end
  end

  # Only update last_active_at every 5 minutes to avoid excessive writes
  defp maybe_touch_session(token_hash, conn) do
    cache_key = "session_touch:#{token_hash}"

    case safe_cache_raw_get(cache_key) do
      nil ->
        ip = get_client_ip(conn)
        safe_cache_raw_set(cache_key, "1", 300)
        Task.start(fn -> Hybridsocial.Auth.touch_session(token_hash, ip) end)

      _ ->
        :ok
    end
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip |> String.split(",") |> hd() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp safe_cache_raw_get(key) do
    try do
      Hybridsocial.Cache.get(key)
    rescue
      _ -> nil
    end
  end

  defp safe_cache_raw_set(key, value, ttl) do
    try do
      Hybridsocial.Cache.set(key, value, ttl)
    rescue
      _ -> :ok
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        {:ok, String.trim(token)}

      _ ->
        # Fallback: httpOnly cookie only (no query params — tokens in URLs leak to logs)
        case conn.cookies["hs_access"] do
          nil -> {:error, :no_token}
          token -> {:ok, token}
        end
    end
  end

  defp fetch_identity(identity_id) do
    case safe_cache_get(identity_id) do
      nil ->
        case Accounts.get_identity(identity_id) do
          nil ->
            nil

          identity ->
            safe_cache_set(identity_id, identity)
            identity
        end

      cached ->
        cached
    end
  end

  defp safe_cache_get(identity_id) do
    try do
      TokenCache.get_cached_identity(identity_id)
    rescue
      _ -> nil
    end
  end

  defp safe_cache_set(identity_id, identity) do
    try do
      TokenCache.cache_identity(identity_id, identity)
    rescue
      _ -> :ok
    end
  end
end

defmodule HybridsocialWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug that halts unauthenticated requests with 401.
  Must be used after HybridsocialWeb.Plugs.Auth.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_identity] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "auth.unauthorized", message: "Authentication required"})
      |> halt()
    end
  end
end

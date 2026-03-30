defmodule HybridsocialWeb.Plugs.FederationRateLimiter do
  @moduledoc """
  ETS-based rate limiter for federation endpoints (no external deps).

  Per-IP rate limiting with configurable limits per action.
  Returns 429 Too Many Requests when exceeded.
  Default: 300 requests per 5 minutes for authenticated, 60 for anonymous.
  """
  import Plug.Conn

  @table :federation_rate_limit
  @default_window 300
  @default_auth_limit 300
  @default_anon_limit 60

  def init(opts), do: opts

  def call(conn, opts) do
    ensure_table()

    identifier = get_identifier(conn)
    window = Keyword.get(opts, :window, @default_window)
    limit = get_limit(conn, opts)
    bucket = current_bucket(window)
    key = {identifier, bucket}

    case increment(key, window) do
      count when count > limit ->
        retry_after = window - rem(System.system_time(:second), window)

        conn
        |> put_resp_header("retry-after", Integer.to_string(max(retry_after, 1)))
        |> put_status(:too_many_requests)
        |> Phoenix.Controller.json(%{error: "Rate limit exceeded"})
        |> halt()

      _ ->
        conn
    end
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [:public, :set, :named_table, read_concurrency: true, write_concurrency: true])
      _ ->
        :ok
    end
  end

  defp get_identifier(conn) do
    case conn.assigns[:current_identity] do
      nil ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()
        "ip:#{ip}"

      identity ->
        "identity:#{identity.id}"
    end
  end

  defp get_limit(conn, opts) do
    if conn.assigns[:current_identity] do
      Keyword.get(opts, :auth_limit, @default_auth_limit)
    else
      Keyword.get(opts, :anon_limit, @default_anon_limit)
    end
  end

  defp current_bucket(window) do
    div(System.system_time(:second), window)
  end

  defp increment(key, window) do
    try do
      :ets.update_counter(@table, key, {2, 1})
    rescue
      ArgumentError ->
        # Key doesn't exist — insert with count 1
        :ets.insert(@table, {key, 1})
        # Schedule cleanup for expired buckets
        spawn(fn -> cleanup_old_buckets(window) end)
        1
    end
  end

  defp cleanup_old_buckets(window) do
    current = current_bucket(window)

    # Delete entries from buckets older than 2 windows ago
    :ets.foldl(
      fn {{_id, bucket} = key, _count}, acc ->
        if bucket < current - 1 do
          :ets.delete(@table, key)
        end
        acc
      end,
      :ok,
      @table
    )
  rescue
    _ -> :ok
  end
end

defmodule HybridsocialWeb.Plugs.RateLimiterTest do
  use HybridsocialWeb.ConnCase, async: false

  alias HybridsocialWeb.Plugs.RateLimiter

  setup do
    # Enable rate limiting for these tests
    Application.put_env(:hybridsocial, :rate_limiting_enabled, true)

    # The anonymous limit comes from Config (default 240). Start the config
    # store (not started in test env) and pin a small limit so the loops
    # below can exceed it. Flush any stale Valkey counters from prior runs
    # since the rate-limiter cache is not sandboxed.
    start_supervised!(Hybridsocial.Config.Store)
    Hybridsocial.Config.set("rate_limit_anonymous", 5)
    Hybridsocial.Cache.flush_pattern("ratelimit:*")

    on_exit(fn ->
      Application.put_env(:hybridsocial, :rate_limiting_enabled, false)
    end)

    :ok
  end

  describe "rate limiting" do
    test "allows requests under the limit", %{conn: conn} do
      conn =
        conn
        |> Map.put(:remote_ip, {192, 168, 1, 100})
        |> RateLimiter.call([])

      refute conn.halted
    end

    test "returns 429 when limit is exceeded", %{conn: conn} do
      # Anonymous limit pinned to 5 in setup; exceed it.
      for _ <- 1..6 do
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 1})
        |> RateLimiter.call([])
      end

      conn =
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 1})
        |> RateLimiter.call([])

      assert conn.halted
      assert conn.status == 429

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "rate_limit.exceeded"
    end

    test "includes Retry-After header when rate limited", %{conn: conn} do
      for _ <- 1..6 do
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 2})
        |> RateLimiter.call([])
      end

      conn =
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 2})
        |> RateLimiter.call([])

      assert conn.halted

      retry_after = Plug.Conn.get_resp_header(conn, "retry-after")
      assert length(retry_after) == 1
    end

    test "authenticated users have higher limit", %{conn: conn} do
      identity = %Hybridsocial.Accounts.Identity{id: Ecto.UUID.generate()}

      # Should not be rate limited at 60 requests (anonymous limit)
      for _ <- 1..60 do
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 3})
        |> Plug.Conn.assign(:current_identity, identity)
        |> RateLimiter.call([])
      end

      result_conn =
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 3})
        |> Plug.Conn.assign(:current_identity, identity)
        |> RateLimiter.call([])

      refute result_conn.halted
    end

    test "different IPs have separate limits", %{conn: conn} do
      for _ <- 1..60 do
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 4})
        |> RateLimiter.call([])
      end

      # Different IP should not be limited
      result_conn =
        conn
        |> Map.put(:remote_ip, {10, 0, 0, 5})
        |> RateLimiter.call([])

      refute result_conn.halted
    end

    test "media proxy requests use their own bucket", %{conn: conn} do
      # Exhaust the anonymous API bucket (pinned to 5).
      for _ <- 1..6 do
        conn |> Map.put(:remote_ip, {10, 0, 0, 6}) |> RateLimiter.call([])
      end

      proxied =
        build_conn(:get, "/proxy/media/sig/url")
        |> Map.put(:remote_ip, {10, 0, 0, 6})
        |> RateLimiter.call([])

      refute proxied.halted

      Hybridsocial.Config.set("rate_limit_media_proxy", 1)

      for _ <- 1..2 do
        build_conn(:get, "/proxy/media/sig/url")
        |> Map.put(:remote_ip, {10, 0, 0, 7})
        |> RateLimiter.call([])
      end

      limited =
        build_conn(:get, "/proxy/media/sig/url")
        |> Map.put(:remote_ip, {10, 0, 0, 7})
        |> RateLimiter.call([])

      assert limited.status == 429
    end
  end
end

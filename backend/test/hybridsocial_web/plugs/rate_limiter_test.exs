defmodule HybridsocialWeb.Plugs.RateLimiterTest do
  use HybridsocialWeb.ConnCase, async: false

  alias HybridsocialWeb.Plugs.RateLimiter

  setup do
    # Enable rate limiting for these tests
    Application.put_env(:hybridsocial, :rate_limiting_enabled, true)

    # Clean up the ETS table between tests
    case :ets.whereis(:rate_limiter) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:rate_limiter)
    end

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
      # Anonymous limit is 60/min
      for _ <- 1..60 do
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
      for _ <- 1..60 do
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
  end
end

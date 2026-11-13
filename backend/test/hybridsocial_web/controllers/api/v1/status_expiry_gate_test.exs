defmodule HybridsocialWeb.Api.V1.StatusExpiryGateTest do
  # async: false — writes runtime config to the shared Config.Store.
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Config

  setup %{conn: conn} do
    start_supervised!(Hybridsocial.Config.Store)
    Config.set("tiers_enabled", true)
    identity = create_user("timergate", "timergate@test.com")
    %{conn: auth_conn(conn, identity)}
  end

  test "a tier with post_expiry allowed can post a timed status", %{conn: conn} do
    conn = post(conn, "/api/v1/statuses", %{"content" => "brief", "expires_in" => 3600})
    assert json_response(conn, 201)["expires_at"]
  end

  test "a tier with post_expiry off is refused", %{conn: conn} do
    Config.set("tier_free_post_expiry", false)

    conn = post(conn, "/api/v1/statuses", %{"content" => "brief", "expires_in" => 3600})
    assert json_response(conn, 422)["error"] == "limits.post_expiry_not_allowed"
  end

  test "an out-of-range lifetime names the bounds", %{conn: conn} do
    conn = post(conn, "/api/v1/statuses", %{"content" => "brief", "expires_in" => 1})
    body = json_response(conn, 422)
    assert body["error"] == "post.expires_in_invalid"
    assert is_integer(body["min"]) and is_integer(body["max"])
  end
end

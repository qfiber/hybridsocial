defmodule HybridsocialWeb.Api.V1.SubscriptionControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts

  defp create_user(handle, email) do
    {:ok, identity} =
      Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  defp auth_conn(conn, identity) do
    {:ok, token, _claims} = Hybridsocial.Auth.Token.generate_access_token(identity.id)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "GET /api/v1/subscriptions/plans" do
    test "returns available plans", %{conn: conn} do
      conn = get(conn, "/api/v1/subscriptions/plans")
      response = json_response(conn, 200)

      assert is_list(response["plans"])
      assert length(response["plans"]) == 2

      plan_ids = Enum.map(response["plans"], & &1["id"])
      assert "free" in plan_ids
      assert "premium" in plan_ids
    end
  end

  describe "POST /api/v1/subscriptions" do
    test "creates a subscription", %{conn: conn} do
      identity = create_user("subtest", "subtest@test.com")

      conn =
        conn
        |> auth_conn(identity)
        |> post("/api/v1/subscriptions", %{"plan" => "premium", "payment_provider" => "stripe"})

      response = json_response(conn, 201)
      assert response["plan"] == "premium"
      assert response["status"] == "active"
      assert response["payment_provider"] == "stripe"
    end

    test "returns 401 without auth", %{conn: conn} do
      conn = post(conn, "/api/v1/subscriptions", %{"plan" => "premium"})
      assert json_response(conn, 401)["error"] == "auth.unauthorized"
    end
  end

  describe "GET /api/v1/subscriptions/current" do
    test "returns current subscription", %{conn: conn} do
      identity = create_user("cursub", "cursub@test.com")
      {:ok, _} = Hybridsocial.Premium.create_subscription(identity.id, %{plan: "premium"})

      conn =
        conn
        |> auth_conn(identity)
        |> get("/api/v1/subscriptions/current")

      response = json_response(conn, 200)
      assert response["plan"] == "premium"
    end

    test "returns free plan when no subscription", %{conn: conn} do
      identity = create_user("nosub3", "nosub3@test.com")

      conn =
        conn
        |> auth_conn(identity)
        |> get("/api/v1/subscriptions/current")

      response = json_response(conn, 200)
      assert response["plan"] == "free"
    end
  end

  describe "DELETE /api/v1/subscriptions" do
    test "cancels subscription", %{conn: conn} do
      identity = create_user("cancelsub", "cancelsub@test.com")
      {:ok, _} = Hybridsocial.Premium.create_subscription(identity.id, %{plan: "premium"})

      conn =
        conn
        |> auth_conn(identity)
        |> delete("/api/v1/subscriptions")

      response = json_response(conn, 200)
      assert response["status"] == "cancelled"
    end

    test "returns 404 when no subscription", %{conn: conn} do
      identity = create_user("nocansub", "nocansub@test.com")

      conn =
        conn
        |> auth_conn(identity)
        |> delete("/api/v1/subscriptions")

      assert json_response(conn, 404)["error"] == "subscription.not_found"
    end
  end

  describe "POST /api/v1/verification/apply" do
    test "applies for verification", %{conn: conn} do
      identity = create_user("verifyme", "verifyme@test.com")

      conn =
        conn
        |> auth_conn(identity)
        |> post("/api/v1/verification/apply", %{"type" => "manual"})

      response = json_response(conn, 201)
      assert response["type"] == "manual"
      assert response["status"] == "pending"
    end
  end

  describe "GET /api/v1/verification/status" do
    test "returns verification status", %{conn: conn} do
      identity = create_user("verifystatus", "verifystatus@test.com")
      {:ok, _} = Hybridsocial.Premium.apply_for_verification(identity.id, "manual")

      conn =
        conn
        |> auth_conn(identity)
        |> get("/api/v1/verification/status")

      response = json_response(conn, 200)
      assert response["status"] == "pending"
    end

    test "returns none when no verification", %{conn: conn} do
      identity = create_user("noverifystatus", "noverifystatus@test.com")

      conn =
        conn
        |> auth_conn(identity)
        |> get("/api/v1/verification/status")

      response = json_response(conn, 200)
      assert response["status"] == "none"
    end
  end
end

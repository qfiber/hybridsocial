defmodule HybridsocialWeb.Api.V1.MigrationControllerTest do
  use HybridsocialWeb.ConnCase

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  defp auth_conn(conn, identity) do
    {:ok, token, _} = Hybridsocial.Auth.Token.generate_access_token(identity.id)

    conn
    |> put_req_header("authorization", "Bearer #{token}")
  end

  describe "POST /api/v1/accounts/also_known_as" do
    setup %{conn: conn} do
      user = create_user("akauser", "akauser@test.com")
      %{conn: auth_conn(conn, user), user: user}
    end

    test "adds an alsoKnownAs URI", %{conn: conn} do
      conn =
        post(conn, "/api/v1/accounts/also_known_as", %{
          "uri" => "https://other.server/actors/123"
        })

      assert %{"also_known_as" => aka} = json_response(conn, 200)
      assert "https://other.server/actors/123" in aka
    end

    test "returns error when uri is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/accounts/also_known_as", %{})
      assert %{"error" => "also_known_as.uri_required"} = json_response(conn, 400)
    end
  end

  describe "POST /api/v1/accounts/migrate" do
    setup %{conn: conn} do
      user = create_user("miguser", "miguser@test.com")
      %{conn: auth_conn(conn, user), user: user}
    end

    test "returns error when target_account is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/accounts/migrate", %{})
      assert %{"error" => "migration.target_required"} = json_response(conn, 400)
    end

    test "returns error for invalid target URL", %{conn: conn} do
      conn =
        post(conn, "/api/v1/accounts/migrate", %{
          "target_account" => "not-a-valid-url"
        })

      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "unauthenticated access" do
    test "returns 401 for unauthenticated migrate request", %{conn: conn} do
      conn = post(conn, "/api/v1/accounts/migrate", %{"target_account" => "https://example.com"})
      assert json_response(conn, 401)["error"] == "auth.unauthorized"
    end

    test "returns 401 for unauthenticated also_known_as request", %{conn: conn} do
      conn = post(conn, "/api/v1/accounts/also_known_as", %{"uri" => "https://example.com"})
      assert json_response(conn, 401)["error"] == "auth.unauthorized"
    end
  end
end

defmodule HybridsocialWeb.Api.V1.AuthAuditLogTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts
  alias Hybridsocial.Moderation

  @valid_attrs %{
    "handle" => "audituser",
    "display_name" => "Audit User",
    "email" => "audit@example.com",
    "password" => "password123",
    "password_confirmation" => "password123"
  }

  describe "audit logging for auth events" do
    test "successful login creates audit log", %{conn: conn} do
      {:ok, _} = Accounts.register_user(@valid_attrs)

      post(conn, "/api/v1/auth/login", %{
        "email" => "audit@example.com",
        "password" => "password123"
      })

      logs = Moderation.list_audit_log(action: "auth.login")
      assert length(logs) > 0
      log = hd(logs)
      assert log.action == "auth.login"
      assert log.details["method"] == "password"
    end

    test "failed login creates audit log", %{conn: conn} do
      {:ok, _} = Accounts.register_user(@valid_attrs)

      post(conn, "/api/v1/auth/login", %{
        "email" => "audit@example.com",
        "password" => "wrongpassword"
      })

      logs = Moderation.list_audit_log(action: "auth.login_failed")
      assert length(logs) > 0
      log = hd(logs)
      assert log.action == "auth.login_failed"
      assert log.details["email"] == "audit@example.com"
    end

    test "logout creates audit log", %{conn: conn} do
      {:ok, _} = Accounts.register_user(@valid_attrs)

      login_conn =
        post(conn, "/api/v1/auth/login", %{
          "email" => "audit@example.com",
          "password" => "password123"
        })

      %{"access_token" => token} = json_response(login_conn, 200)

      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/auth/logout")

      logs = Moderation.list_audit_log(action: "auth.logout")
      assert length(logs) > 0
      assert hd(logs).action == "auth.logout"
    end

    test "registration creates audit log", %{conn: conn} do
      post(conn, "/api/v1/auth/register", @valid_attrs)

      logs = Moderation.list_audit_log(action: "auth.register")
      assert length(logs) > 0
      log = hd(logs)
      assert log.action == "auth.register"
      assert log.details["handle"] == "audituser"
    end
  end
end

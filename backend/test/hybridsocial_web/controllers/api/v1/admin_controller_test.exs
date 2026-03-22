defmodule HybridsocialWeb.Api.V1.AdminControllerTest do
  use HybridsocialWeb.ConnCase

  alias Hybridsocial.Moderation
  alias Hybridsocial.Auth.RBAC

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

  defp make_admin(identity) do
    {:ok, _} = RBAC.assign_role(identity.id, "owner", identity.id)
    identity
  end

  defp make_moderator(identity) do
    {:ok, _} = RBAC.assign_role(identity.id, "moderator", identity.id)
    identity
  end

  defp auth_conn(conn, identity) do
    {:ok, token, _} = Hybridsocial.Auth.Token.generate_access_token(identity.id)

    conn
    |> put_req_header("authorization", "Bearer #{token}")
  end

  describe "admin reports" do
    setup %{conn: conn} do
      admin = create_user("admin1", "admin1@test.com") |> make_admin()
      user = create_user("user1", "user1@test.com")
      reported = create_user("reported1", "reported1@test.com")

      {:ok, report} =
        Moderation.create_report(user.id, %{
          "reported_id" => reported.id,
          "category" => "spam",
          "description" => "Test report"
        })

      %{
        conn: auth_conn(conn, admin),
        admin: admin,
        user: user,
        reported: reported,
        report: report
      }
    end

    test "GET /api/v1/admin/reports lists reports", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/reports")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 1
    end

    test "GET /api/v1/admin/reports/:id shows a report", %{conn: conn, report: report} do
      conn = get(conn, "/api/v1/admin/reports/#{report.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == report.id
    end

    test "POST /api/v1/admin/reports/:id/resolve resolves report", %{conn: conn, report: report} do
      conn =
        post(conn, "/api/v1/admin/reports/#{report.id}/resolve", %{"action_taken" => "warned"})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "resolved"
      assert data["action_taken"] == "warned"
    end

    test "POST /api/v1/admin/reports/:id/assign assigns report", %{
      conn: conn,
      report: report,
      admin: admin
    } do
      conn = post(conn, "/api/v1/admin/reports/#{report.id}/assign", %{})
      assert %{"data" => data} = json_response(conn, 200)
      assert data["status"] == "investigating"
      assert data["assigned_to"] == admin.id
    end
  end

  describe "moderator access" do
    setup %{conn: conn} do
      moderator = create_user("mod1", "mod1@test.com") |> make_moderator()
      user = create_user("user2", "user2@test.com")
      reported = create_user("reported2", "reported2@test.com")

      {:ok, report} =
        Moderation.create_report(user.id, %{
          "reported_id" => reported.id,
          "category" => "spam",
          "description" => "Test report"
        })

      %{conn: auth_conn(conn, moderator), moderator: moderator, report: report}
    end

    test "moderator can view reports", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/reports")
      assert %{"data" => _} = json_response(conn, 200)
    end

    test "moderator can view audit log", %{conn: conn, moderator: moderator} do
      Moderation.log(moderator.id, "test.action", nil, nil, %{})
      conn = get(conn, "/api/v1/admin/audit_log")
      assert %{"data" => _} = json_response(conn, 200)
    end

    test "moderator cannot manage federation", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/banned_domains")
      assert json_response(conn, 403)["error"] == "permission.denied"
    end

    test "moderator cannot manage relays", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/relays")
      assert json_response(conn, 403)["error"] == "permission.denied"
    end
  end

  describe "admin audit log" do
    setup %{conn: conn} do
      admin = create_user("admin2", "admin2@test.com") |> make_admin()
      Moderation.log(admin.id, "test.action", nil, nil, %{})

      %{conn: auth_conn(conn, admin), admin: admin}
    end

    test "GET /api/v1/admin/audit_log lists entries", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/audit_log")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) >= 1
    end
  end

  describe "admin accounts" do
    setup %{conn: conn} do
      admin = create_user("admin3", "admin3@test.com") |> make_admin()
      user = create_user("target1", "target1@test.com")

      %{conn: auth_conn(conn, admin), admin: admin, user: user}
    end

    test "GET /api/v1/admin/accounts lists accounts", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/accounts")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) >= 2
    end

    test "POST /api/v1/admin/accounts/:id/action suspends user", %{conn: conn, user: user} do
      conn = post(conn, "/api/v1/admin/accounts/#{user.id}/action", %{"action" => "suspend"})
      assert %{"data" => data} = json_response(conn, 200)
      assert data["is_suspended"] == true
    end

    test "POST /api/v1/admin/accounts/:id/action unsuspends user", %{conn: conn, user: user} do
      # First suspend
      post(conn, "/api/v1/admin/accounts/#{user.id}/action", %{"action" => "suspend"})
      # Then unsuspend
      conn = post(conn, "/api/v1/admin/accounts/#{user.id}/action", %{"action" => "unsuspend"})
      assert %{"data" => data} = json_response(conn, 200)
      assert data["is_suspended"] == false
    end

    test "POST /api/v1/admin/accounts/:id/action warns user", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/v1/admin/accounts/#{user.id}/action", %{
          "action" => "warn",
          "reason" => "Violation"
        })

      assert %{"data" => _data, "message" => "account.warned"} = json_response(conn, 200)
    end
  end

  describe "admin content filters" do
    setup %{conn: conn} do
      admin = create_user("admin4", "admin4@test.com") |> make_admin()

      %{conn: auth_conn(conn, admin), admin: admin}
    end

    test "POST /api/v1/admin/content_filters creates a filter", %{conn: conn} do
      params = %{"type" => "word", "pattern" => "badword", "action" => "reject"}
      conn = post(conn, "/api/v1/admin/content_filters", params)
      assert %{"data" => data} = json_response(conn, 201)
      assert data["pattern"] == "badword"
    end

    test "GET /api/v1/admin/content_filters lists filters", %{conn: conn} do
      Moderation.create_filter(%{"type" => "word", "pattern" => "bad", "action" => "reject"})

      conn = get(conn, "/api/v1/admin/content_filters")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 1
    end

    test "DELETE /api/v1/admin/content_filters/:id deletes a filter", %{conn: conn} do
      {:ok, filter} =
        Moderation.create_filter(%{"type" => "word", "pattern" => "bad", "action" => "reject"})

      conn = delete(conn, "/api/v1/admin/content_filters/#{filter.id}")
      assert json_response(conn, 200)["message"] == "filter.deleted"
    end
  end

  describe "admin banned domains" do
    setup %{conn: conn} do
      admin = create_user("admin5", "admin5@test.com") |> make_admin()

      %{conn: auth_conn(conn, admin), admin: admin}
    end

    test "POST /api/v1/admin/banned_domains bans a domain", %{conn: conn} do
      params = %{"domain" => "spam.com", "type" => "email", "reason" => "Spam"}
      conn = post(conn, "/api/v1/admin/banned_domains", params)
      assert %{"data" => data} = json_response(conn, 201)
      assert data["domain"] == "spam.com"
    end

    test "GET /api/v1/admin/banned_domains lists banned domains", %{conn: conn, admin: admin} do
      Moderation.ban_domain("spam.com", "email", "reason", admin.id)

      conn = get(conn, "/api/v1/admin/banned_domains")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 1
    end

    test "DELETE /api/v1/admin/banned_domains/:domain unbans a domain", %{
      conn: conn,
      admin: admin
    } do
      Moderation.ban_domain("spam.com", "email", "reason", admin.id)

      conn = delete(conn, "/api/v1/admin/banned_domains/spam.com")
      assert json_response(conn, 200)["message"] == "domain.unbanned"
    end
  end

  describe "non-admin access" do
    test "returns 403 for non-admin users", %{conn: conn} do
      user = create_user("regular1", "regular1@test.com")
      conn = auth_conn(conn, user)

      conn = get(conn, "/api/v1/admin/reports")
      assert json_response(conn, 403)["error"] == "auth.forbidden"
    end

    test "returns 401 for unauthenticated users", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/reports")
      assert json_response(conn, 401)["error"] == "auth.unauthorized"
    end
  end

  describe "permission-based access control" do
    test "community_manager cannot access reports", %{conn: conn} do
      cm = create_user("cm1", "cm1@test.com")
      {:ok, _} = RBAC.assign_role(cm.id, "community_manager", cm.id)
      conn = auth_conn(conn, cm)

      conn = get(conn, "/api/v1/admin/reports")
      assert json_response(conn, 403)["error"] == "permission.denied"
    end

    test "community_manager can access content filters", %{conn: conn} do
      cm = create_user("cm2", "cm2@test.com")
      {:ok, _} = RBAC.assign_role(cm.id, "community_manager", cm.id)
      conn = auth_conn(conn, cm)

      conn = get(conn, "/api/v1/admin/content_filters")
      assert %{"data" => _} = json_response(conn, 200)
    end
  end
end

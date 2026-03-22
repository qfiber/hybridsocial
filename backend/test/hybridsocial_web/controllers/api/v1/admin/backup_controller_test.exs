defmodule HybridsocialWeb.Api.V1.Admin.BackupControllerTest do
  use HybridsocialWeb.ConnCase

  defp create_admin(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    {:ok, _} = Hybridsocial.Auth.RBAC.assign_role(identity.id, "owner", identity.id)
    Hybridsocial.Accounts.get_identity!(identity.id)
  end

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

  describe "POST /api/v1/admin/backup" do
    setup %{conn: conn} do
      admin = create_admin("bkadmin1", "bkadmin1@test.com")
      %{conn: auth_conn(conn, admin), admin: admin}
    end

    test "creates a backup job", %{conn: conn} do
      conn = post(conn, "/api/v1/admin/backup", %{"passphrase" => "my-secret", "type" => "full"})
      assert %{"data" => data} = json_response(conn, 202)
      assert data["type"] == "full"
      assert data["status"] == "pending"
    end

    test "requires passphrase", %{conn: conn} do
      conn = post(conn, "/api/v1/admin/backup", %{"type" => "full"})
      assert %{"error" => "backup.passphrase_required"} = json_response(conn, 400)
    end

    test "defaults to full type", %{conn: conn} do
      conn = post(conn, "/api/v1/admin/backup", %{"passphrase" => "secret"})
      assert %{"data" => data} = json_response(conn, 202)
      assert data["type"] == "full"
    end
  end

  describe "GET /api/v1/admin/backups" do
    setup %{conn: conn} do
      admin = create_admin("bkadmin2", "bkadmin2@test.com")
      conn = auth_conn(conn, admin)

      # Create a backup job directly
      {:ok, backup} =
        Hybridsocial.Admin.Backup.create_backup(admin.id, "secret", "full")

      %{conn: conn, admin: admin, backup: backup}
    end

    test "lists all backup jobs", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/backups")
      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) >= 1
    end
  end

  describe "GET /api/v1/admin/backups/:id" do
    setup %{conn: conn} do
      admin = create_admin("bkadmin3", "bkadmin3@test.com")
      conn = auth_conn(conn, admin)

      {:ok, backup} =
        Hybridsocial.Admin.Backup.create_backup(admin.id, "secret", "full")

      %{conn: conn, admin: admin, backup: backup}
    end

    test "shows a backup job", %{conn: conn, backup: backup} do
      conn = get(conn, "/api/v1/admin/backups/#{backup.id}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == backup.id
    end

    test "returns 404 for non-existent backup", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/backups/#{Ecto.UUID.generate()}")
      assert %{"error" => "backup.not_found"} = json_response(conn, 404)
    end
  end

  describe "non-admin access" do
    test "returns 403 for non-admin users", %{conn: conn} do
      user = create_user("bkregular", "bkregular@test.com")
      conn = auth_conn(conn, user)

      conn = get(conn, "/api/v1/admin/backups")
      assert json_response(conn, 403)["error"] == "auth.forbidden"
    end

    test "returns 401 for unauthenticated users", %{conn: conn} do
      conn = get(conn, "/api/v1/admin/backups")
      assert json_response(conn, 401)["error"] == "auth.unauthorized"
    end
  end
end

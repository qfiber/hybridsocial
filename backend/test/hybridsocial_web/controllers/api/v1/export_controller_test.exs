defmodule HybridsocialWeb.Api.V1.ExportControllerTest do
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

  describe "POST /api/v1/export" do
    test "creates an export request", %{conn: conn} do
      identity = create_user("exporttest", "exporttest@test.com")

      conn =
        conn
        |> auth_conn(identity)
        |> post("/api/v1/export")

      response = json_response(conn, 202)
      assert response["status"] == "pending"
      assert response["id"] != nil
    end

    test "returns 401 without auth", %{conn: conn} do
      conn = post(conn, "/api/v1/export")
      assert json_response(conn, 401)["error"] == "auth.unauthorized"
    end
  end

  describe "GET /api/v1/export" do
    test "lists exports", %{conn: conn} do
      identity = create_user("listexp", "listexp@test.com")
      {:ok, _} = Hybridsocial.Portability.request_export(identity.id)

      conn =
        conn
        |> auth_conn(identity)
        |> get("/api/v1/export")

      response = json_response(conn, 200)
      assert is_list(response["exports"])
      assert length(response["exports"]) == 1
    end
  end

  describe "GET /api/v1/export/:id" do
    test "returns specific export", %{conn: conn} do
      identity = create_user("showexp", "showexp@test.com")
      {:ok, export} = Hybridsocial.Portability.request_export(identity.id)

      conn =
        conn
        |> auth_conn(identity)
        |> get("/api/v1/export/#{export.id}")

      response = json_response(conn, 200)
      assert response["id"] == export.id
    end

    test "returns 404 for other user's export", %{conn: conn} do
      identity1 = create_user("showexp1", "showexp1@test.com")
      identity2 = create_user("showexp2", "showexp2@test.com")
      {:ok, export} = Hybridsocial.Portability.request_export(identity1.id)

      conn =
        conn
        |> auth_conn(identity2)
        |> get("/api/v1/export/#{export.id}")

      assert json_response(conn, 404)["error"] == "export.not_found"
    end
  end

  describe "POST /api/v1/import" do
    test "returns error for invalid type", %{conn: conn} do
      identity = create_user("importtest", "importtest@test.com")

      conn =
        conn
        |> auth_conn(identity)
        |> post("/api/v1/import", %{"type" => "invalid", "data" => "test"})

      assert json_response(conn, 422)["error"] == "import.invalid_type"
    end

    test "returns error for missing params", %{conn: conn} do
      identity = create_user("importtest2", "importtest2@test.com")

      conn =
        conn
        |> auth_conn(identity)
        |> post("/api/v1/import", %{})

      assert json_response(conn, 422)["error"] == "import.missing_params"
    end

    test "imports follows from CSV", %{conn: conn} do
      identity = create_user("importfol", "importfol@test.com")
      _target = create_user("targetfol", "targetfol@test.com")

      csv_data = "targetfol\nnonexistent_user"

      conn =
        conn
        |> auth_conn(identity)
        |> post("/api/v1/import", %{"type" => "follows", "data" => csv_data})

      response = json_response(conn, 200)
      assert response["imported"] == 1
      assert response["failed"] == 1
    end
  end
end

defmodule HybridsocialWeb.Api.V1.PageControllerTest do
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Auth.Token
  alias Hybridsocial.Pages

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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

  defp authenticate(conn, identity) do
    {:ok, access_token, _claims} = Token.generate_access_token(identity.id)

    conn
    |> put_req_header("authorization", "Bearer #{access_token}")
  end

  defp create_test_page(owner, handle) do
    {:ok, page} =
      Pages.create_page(owner.id, %{
        "handle" => handle,
        "display_name" => "Test Page #{handle}",
        "bio" => "A test page",
        "website" => "https://example.com",
        "category" => "tech"
      })

    page
  end

  # ---------------------------------------------------------------------------
  # Page CRUD
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/pages" do
    test "creates a page", %{conn: conn} do
      owner = create_user("pc_create1", "pc_create1@example.com")

      conn =
        conn
        |> authenticate(owner)
        |> post("/api/v1/pages", %{
          "handle" => "new_page",
          "display_name" => "New Page",
          "bio" => "A brand new page",
          "website" => "https://example.com",
          "category" => "tech"
        })

      response = json_response(conn, 201)
      assert response["handle"] == "new_page"
      assert response["display_name"] == "New Page"
      assert response["organization"]["owner_id"] == owner.id
    end

    test "requires authentication", %{conn: conn} do
      conn = post(conn, "/api/v1/pages", %{"handle" => "unauth_page"})
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/pages" do
    test "lists pages", %{conn: conn} do
      owner = create_user("pc_list1", "pc_list1@example.com")
      _page = create_test_page(owner, "list_pg1")

      conn = get(conn, "/api/v1/pages")

      response = json_response(conn, 200)
      assert is_list(response)
      assert length(response) >= 1
    end
  end

  describe "GET /api/v1/pages/:id" do
    test "shows a page with branding", %{conn: conn} do
      owner = create_user("pc_show1", "pc_show1@example.com")
      page = create_test_page(owner, "show_pg1")

      conn = get(conn, "/api/v1/pages/#{page.id}")

      response = json_response(conn, 200)
      assert response["handle"] == "show_pg1"
      assert response["organization"]["website"] == "https://example.com"
    end

    test "returns 404 for non-existent page", %{conn: conn} do
      conn = get(conn, "/api/v1/pages/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/v1/pages/:id" do
    test "owner updates a page", %{conn: conn} do
      owner = create_user("pc_upd1", "pc_upd1@example.com")
      page = create_test_page(owner, "upd_pg1")

      conn =
        conn
        |> authenticate(owner)
        |> patch("/api/v1/pages/#{page.id}", %{"display_name" => "Updated"})

      response = json_response(conn, 200)
      assert response["display_name"] == "Updated"
    end

    test "non-authorized user gets forbidden", %{conn: conn} do
      owner = create_user("pc_upd2", "pc_upd2@example.com")
      rando = create_user("pc_upd3", "pc_upd3@example.com")
      page = create_test_page(owner, "upd_pg2")

      conn =
        conn
        |> authenticate(rando)
        |> patch("/api/v1/pages/#{page.id}", %{"display_name" => "Hacked"})

      assert json_response(conn, 403)
    end
  end

  describe "DELETE /api/v1/pages/:id" do
    test "owner deletes a page", %{conn: conn} do
      owner = create_user("pc_del1", "pc_del1@example.com")
      page = create_test_page(owner, "del_pg1")

      conn =
        conn
        |> authenticate(owner)
        |> delete("/api/v1/pages/#{page.id}")

      assert response(conn, 204)
    end

    test "non-owner gets forbidden", %{conn: conn} do
      owner = create_user("pc_del2", "pc_del2@example.com")
      rando = create_user("pc_del3", "pc_del3@example.com")
      page = create_test_page(owner, "del_pg2")

      conn =
        conn
        |> authenticate(rando)
        |> delete("/api/v1/pages/#{page.id}")

      assert json_response(conn, 403)
    end
  end

  # ---------------------------------------------------------------------------
  # Roles
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/pages/:id/roles" do
    test "lists roles", %{conn: conn} do
      owner = create_user("pc_roles1", "pc_roles1@example.com")
      user = create_user("pc_roles2", "pc_roles2@example.com")
      page = create_test_page(owner, "roles_pg1")
      {:ok, _} = Pages.add_role(page.id, owner.id, user.id, "editor")

      conn = get(conn, "/api/v1/pages/#{page.id}/roles")

      response = json_response(conn, 200)
      assert length(response) == 1
      assert hd(response)["role"] == "editor"
    end
  end

  describe "POST /api/v1/pages/:id/roles" do
    test "owner adds a role", %{conn: conn} do
      owner = create_user("pc_addrole1", "pc_addrole1@example.com")
      user = create_user("pc_addrole2", "pc_addrole2@example.com")
      page = create_test_page(owner, "addrole_pg1")

      conn =
        conn
        |> authenticate(owner)
        |> post("/api/v1/pages/#{page.id}/roles", %{
          "identity_id" => user.id,
          "role" => "editor"
        })

      response = json_response(conn, 201)
      assert response["role"] == "editor"
      assert response["identity_id"] == user.id
    end

    test "non-admin cannot add role", %{conn: conn} do
      owner = create_user("pc_addrole3", "pc_addrole3@example.com")
      rando = create_user("pc_addrole4", "pc_addrole4@example.com")
      user = create_user("pc_addrole5", "pc_addrole5@example.com")
      page = create_test_page(owner, "addrole_pg2")

      conn =
        conn
        |> authenticate(rando)
        |> post("/api/v1/pages/#{page.id}/roles", %{
          "identity_id" => user.id,
          "role" => "editor"
        })

      assert json_response(conn, 403)
    end
  end

  describe "DELETE /api/v1/pages/:id/roles/:role_id" do
    test "owner removes a role", %{conn: conn} do
      owner = create_user("pc_rmrole1", "pc_rmrole1@example.com")
      user = create_user("pc_rmrole2", "pc_rmrole2@example.com")
      page = create_test_page(owner, "rmrole_pg1")
      {:ok, role} = Pages.add_role(page.id, owner.id, user.id, "editor")

      conn =
        conn
        |> authenticate(owner)
        |> delete("/api/v1/pages/#{page.id}/roles/#{role.id}")

      assert response(conn, 204)
    end
  end

  # ---------------------------------------------------------------------------
  # Branding
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/pages/:id/branding" do
    test "returns default branding when none exists", %{conn: conn} do
      owner = create_user("pc_brand1", "pc_brand1@example.com")
      page = create_test_page(owner, "brand_pg1")

      conn = get(conn, "/api/v1/pages/#{page.id}/branding")

      response = json_response(conn, 200)
      assert response["identity_id"] == page.id
      assert response["theme_color"] == nil
    end
  end

  describe "PATCH /api/v1/pages/:id/branding" do
    test "owner updates branding", %{conn: conn} do
      owner = create_user("pc_brand2", "pc_brand2@example.com")
      page = create_test_page(owner, "brand_pg2")

      conn =
        conn
        |> authenticate(owner)
        |> patch("/api/v1/pages/#{page.id}/branding", %{
          "theme_color" => "#ff0000",
          "logo_url" => "https://example.com/logo.png"
        })

      response = json_response(conn, 200)
      assert response["theme_color"] == "#ff0000"
      assert response["logo_url"] == "https://example.com/logo.png"
    end

    test "non-admin cannot update branding", %{conn: conn} do
      owner = create_user("pc_brand3", "pc_brand3@example.com")
      rando = create_user("pc_brand4", "pc_brand4@example.com")
      page = create_test_page(owner, "brand_pg3")

      conn =
        conn
        |> authenticate(rando)
        |> patch("/api/v1/pages/#{page.id}/branding", %{"theme_color" => "#ff0000"})

      assert json_response(conn, 403)
    end
  end
end

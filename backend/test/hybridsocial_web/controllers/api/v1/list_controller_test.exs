defmodule HybridsocialWeb.Api.V1.ListControllerTest do
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Auth.Token

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "Password123!!",
        "password_confirmation" => "Password123!!"
      })

    identity
  end

  defp authenticate(conn, identity) do
    {:ok, access_token, _claims} = Token.generate_access_token(identity.id)

    conn
    |> put_req_header("authorization", "Bearer #{access_token}")
  end

  # ---------------------------------------------------------------------------
  # List CRUD
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/lists" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/lists")
      assert json_response(conn, 401)
    end

    test "returns empty list when no lists exist", %{conn: conn} do
      alice = create_user("lc_alice", "lc_alice@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/lists")

      assert json_response(conn, 200) == []
    end

    test "returns user's lists", %{conn: conn} do
      alice = create_user("lc_alice2", "lc_alice2@example.com")
      {:ok, _} = Hybridsocial.Social.Lists.create_list(alice.id, "My List")

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/lists")

      response = json_response(conn, 200)
      assert length(response) == 1
      assert hd(response)["name"] == "My List"
    end
  end

  describe "POST /api/v1/lists" do
    test "creates a list", %{conn: conn} do
      alice = create_user("lc_create", "lc_create@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/lists", %{"name" => "New List"})

      response = json_response(conn, 201)
      assert response["name"] == "New List"
      assert response["id"] != nil
    end

    test "returns error without name", %{conn: conn} do
      alice = create_user("lc_create2", "lc_create2@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/lists", %{})

      assert json_response(conn, 422)
    end
  end

  describe "GET /api/v1/lists/:id" do
    test "shows a list", %{conn: conn} do
      alice = create_user("lc_show", "lc_show@example.com")
      {:ok, list} = Hybridsocial.Social.Lists.create_list(alice.id, "Show Me")

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/lists/#{list.id}")

      response = json_response(conn, 200)
      assert response["name"] == "Show Me"
    end

    test "returns 404 for non-existent list", %{conn: conn} do
      alice = create_user("lc_show2", "lc_show2@example.com")

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/lists/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/v1/lists/:id" do
    test "updates a list", %{conn: conn} do
      alice = create_user("lc_patch", "lc_patch@example.com")
      {:ok, list} = Hybridsocial.Social.Lists.create_list(alice.id, "Old Name")

      conn =
        conn
        |> authenticate(alice)
        |> patch("/api/v1/lists/#{list.id}", %{"name" => "New Name"})

      response = json_response(conn, 200)
      assert response["name"] == "New Name"
    end

    test "returns 404 when not owner", %{conn: conn} do
      alice = create_user("lc_patch2", "lc_patch2@example.com")
      bob = create_user("lc_patch3", "lc_patch3@example.com")
      {:ok, list} = Hybridsocial.Social.Lists.create_list(alice.id, "Alice's List")

      conn =
        conn
        |> authenticate(bob)
        |> patch("/api/v1/lists/#{list.id}", %{"name" => "Hacked"})

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/lists/:id" do
    test "deletes a list", %{conn: conn} do
      alice = create_user("lc_del", "lc_del@example.com")
      {:ok, list} = Hybridsocial.Social.Lists.create_list(alice.id, "Delete Me")

      conn =
        conn
        |> authenticate(alice)
        |> delete("/api/v1/lists/#{list.id}")

      assert response(conn, 204)
    end

    test "returns 404 when not owner", %{conn: conn} do
      alice = create_user("lc_del2", "lc_del2@example.com")
      bob = create_user("lc_del3", "lc_del3@example.com")
      {:ok, list} = Hybridsocial.Social.Lists.create_list(alice.id, "Alice's List")

      conn =
        conn
        |> authenticate(bob)
        |> delete("/api/v1/lists/#{list.id}")

      assert json_response(conn, 404)
    end
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/lists/:id/accounts" do
    test "returns list members", %{conn: conn} do
      alice = create_user("lc_mem", "lc_mem@example.com")
      bob = create_user("lc_mem2", "lc_mem2@example.com")
      {:ok, list} = Hybridsocial.Social.Lists.create_list(alice.id, "Friends")
      {:ok, _} = Hybridsocial.Social.Lists.add_to_list(list.id, alice.id, bob.id)

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/lists/#{list.id}/accounts")

      response = json_response(conn, 200)
      assert length(response) == 1
      assert hd(response)["id"] == bob.id
    end
  end

  describe "POST /api/v1/lists/:id/accounts" do
    test "adds members to list", %{conn: conn} do
      alice = create_user("lc_addm", "lc_addm@example.com")
      bob = create_user("lc_addm2", "lc_addm2@example.com")
      {:ok, list} = Hybridsocial.Social.Lists.create_list(alice.id, "Friends")

      conn =
        conn
        |> authenticate(alice)
        |> post("/api/v1/lists/#{list.id}/accounts", %{"account_ids" => [bob.id]})

      assert response(conn, 204)

      members = Hybridsocial.Social.Lists.list_members(list.id)
      assert length(members) == 1
    end

    test "returns 404 when not owner", %{conn: conn} do
      alice = create_user("lc_addm3", "lc_addm3@example.com")
      bob = create_user("lc_addm4", "lc_addm4@example.com")
      carol = create_user("lc_addm5", "lc_addm5@example.com")
      {:ok, list} = Hybridsocial.Social.Lists.create_list(alice.id, "Friends")

      conn =
        conn
        |> authenticate(bob)
        |> post("/api/v1/lists/#{list.id}/accounts", %{"account_ids" => [carol.id]})

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/lists/:id/accounts" do
    test "removes members from list", %{conn: conn} do
      alice = create_user("lc_rmm", "lc_rmm@example.com")
      bob = create_user("lc_rmm2", "lc_rmm2@example.com")
      {:ok, list} = Hybridsocial.Social.Lists.create_list(alice.id, "Friends")
      {:ok, _} = Hybridsocial.Social.Lists.add_to_list(list.id, alice.id, bob.id)

      conn =
        conn
        |> authenticate(alice)
        |> delete("/api/v1/lists/#{list.id}/accounts", %{"account_ids" => [bob.id]})

      assert response(conn, 204)

      members = Hybridsocial.Social.Lists.list_members(list.id)
      assert members == []
    end
  end
end

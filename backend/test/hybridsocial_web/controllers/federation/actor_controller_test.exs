defmodule HybridsocialWeb.Federation.ActorControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity

  setup do
    {:ok, identity} =
      %Identity{}
      |> Identity.create_changeset(%{
        "type" => "user",
        "handle" => "testactor",
        "display_name" => "Test Actor"
      })
      |> Repo.insert()

    %{identity: identity}
  end

  describe "GET /actors/:id" do
    test "returns AP Actor JSON-LD for valid identity", %{conn: conn, identity: identity} do
      conn = get(conn, "/actors/#{identity.id}")

      body = json_response(conn, 200)

      assert body["@context"] == [
               "https://www.w3.org/ns/activitystreams",
               "https://w3id.org/security/v1"
             ]

      assert body["type"] == "Person"
      assert body["preferredUsername"] == "testactor"
      assert body["name"] == "Test Actor"
      assert String.ends_with?(body["inbox"], "/inbox")
      assert String.ends_with?(body["outbox"], "/outbox")
      assert String.ends_with?(body["followers"], "/followers")
      assert String.ends_with?(body["following"], "/following")

      assert body["publicKey"]["publicKeyPem"] != nil
      assert String.contains?(body["publicKey"]["id"], "#main-key")
    end

    test "returns 404 for unknown identity", %{conn: conn} do
      conn = get(conn, "/actors/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "GET /actors/:id/followers" do
    test "returns OrderedCollection", %{conn: conn, identity: identity} do
      conn = get(conn, "/actors/#{identity.id}/followers")

      body = json_response(conn, 200)
      assert body["type"] == "OrderedCollection"
      assert body["totalItems"] == 0
      assert is_list(body["orderedItems"])
    end

    test "returns 404 for unknown identity", %{conn: conn} do
      conn = get(conn, "/actors/#{Ecto.UUID.generate()}/followers")
      assert json_response(conn, 404)
    end
  end

  describe "GET /actors/:id/following" do
    test "returns OrderedCollection", %{conn: conn, identity: identity} do
      conn = get(conn, "/actors/#{identity.id}/following")

      body = json_response(conn, 200)
      assert body["type"] == "OrderedCollection"
      assert body["totalItems"] == 0
    end

    test "returns 404 for unknown identity", %{conn: conn} do
      conn = get(conn, "/actors/#{Ecto.UUID.generate()}/following")
      assert json_response(conn, 404)
    end
  end

  describe "GET /actors/:id/outbox" do
    test "returns OrderedCollection", %{conn: conn, identity: identity} do
      conn = get(conn, "/actors/#{identity.id}/outbox")

      body = json_response(conn, 200)
      assert body["type"] == "OrderedCollection"
      assert body["totalItems"] == 0
    end

    test "returns 404 for unknown identity", %{conn: conn} do
      conn = get(conn, "/actors/#{Ecto.UUID.generate()}/outbox")
      assert json_response(conn, 404)
    end
  end
end

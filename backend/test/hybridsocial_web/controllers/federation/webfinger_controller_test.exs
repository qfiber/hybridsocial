defmodule HybridsocialWeb.Federation.WebfingerControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity

  setup do
    # Create a test identity
    {:ok, identity} =
      %Identity{}
      |> Identity.create_changeset(%{
        "type" => "user",
        "handle" => "testwebfinger",
        "display_name" => "Test User"
      })
      |> Repo.insert()

    %{identity: identity}
  end

  describe "GET /.well-known/webfinger" do
    # Mastodon re-resolves a stale actor by WebFinger before refetching its
    # key. A 404 for the instance actor made it refuse every signed GET we
    # made: "Could not refresh public key .../actor#main-key".
    test "resolves the instance actor by its handle (acct:domain@domain)", %{conn: conn} do
      domain = HybridsocialWeb.Endpoint.host()
      actor = Hybridsocial.Federation.InstanceActor.ap_id()

      body =
        json_response(get(conn, "/.well-known/webfinger?resource=acct:#{domain}@#{domain}"), 200)

      assert body["subject"] == "acct:#{domain}@#{domain}"

      assert %{"type" => "application/activity+json", "href" => ^actor} =
               Enum.find(body["links"], &(&1["rel"] == "self"))
    end

    test "resolves the instance actor by its URL", %{conn: conn} do
      actor = Hybridsocial.Federation.InstanceActor.ap_id()
      body = json_response(get(conn, "/.well-known/webfinger", %{"resource" => actor}), 200)
      assert Enum.any?(body["links"], &(&1["rel"] == "self" and &1["href"] == actor))
    end

    test "returns JRD for valid local user", %{conn: conn, identity: identity} do
      domain = HybridsocialWeb.Endpoint.host()
      resource = "acct:#{identity.handle}@#{domain}"

      conn = get(conn, "/.well-known/webfinger?resource=#{resource}")

      assert json_response(conn, 200)
      body = json_response(conn, 200)

      assert body["subject"] == resource
      assert is_list(body["links"])

      self_link =
        Enum.find(body["links"], fn l ->
          l["rel"] == "self" && l["type"] == "application/activity+json"
        end)

      assert self_link != nil
      assert self_link["href"] == identity.ap_actor_url
    end

    test "returns 404 for unknown user", %{conn: conn} do
      domain = HybridsocialWeb.Endpoint.host()
      resource = "acct:nonexistent@#{domain}"

      conn = get(conn, "/.well-known/webfinger?resource=#{resource}")
      assert json_response(conn, 404)
    end

    test "returns 404 for non-local domain", %{conn: conn} do
      resource = "acct:someone@remote.example"

      conn = get(conn, "/.well-known/webfinger?resource=#{resource}")
      assert json_response(conn, 404)
    end

    test "returns 400 for invalid resource", %{conn: conn} do
      conn = get(conn, "/.well-known/webfinger?resource=invalid")
      assert json_response(conn, 400)
    end

    test "returns 400 for missing resource parameter", %{conn: conn} do
      conn = get(conn, "/.well-known/webfinger")
      assert json_response(conn, 400)
    end
  end
end

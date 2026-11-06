defmodule HybridsocialWeb.Api.V1.AccountProfileUpdateTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Repo

  @path "/api/v1/accounts/update_credentials"

  setup %{conn: conn} do
    identity = create_user("prof#{System.unique_integer([:positive])}")
    %{conn: auth_conn(conn, identity), identity: identity}
  end

  defp metadata(identity), do: Repo.get!(Identity, identity.id).metadata

  defp field(n), do: %{"name" => "name #{n}", "value" => "value #{n}"}

  describe "metadata" do
    test "a client-sent metadata map is ignored", %{conn: conn, identity: identity} do
      conn |> patch(@path, %{"metadata" => %{"anything" => "else"}}) |> json_response(200)

      refute Map.has_key?(metadata(identity), "anything")
    end

    test "it can't replace what's already there", %{conn: conn, identity: identity} do
      identity |> Ecto.Changeset.change(metadata: %{"staff_key" => 1}) |> Repo.update!()

      conn |> patch(@path, %{"metadata" => %{"staff_key" => 0}}) |> json_response(200)
      conn |> patch(@path, %{"metadata" => %{}}) |> json_response(200)

      assert metadata(identity)["staff_key"] == 1
    end

    test "profile fields can't be smuggled past the cap through it", %{
      conn: conn,
      identity: identity
    } do
      fields = Enum.map(1..50, &field/1)

      conn |> patch(@path, %{"metadata" => %{"profile_fields" => fields}}) |> json_response(200)

      refute Map.has_key?(metadata(identity), "profile_fields")
    end

    test "other profile fields still save alongside an ignored one", %{
      conn: conn,
      identity: identity
    } do
      body =
        conn
        |> patch(@path, %{"display_name" => "New name", "metadata" => %{"anything" => "else"}})
        |> json_response(200)

      assert body["display_name"] == "New name"
      refute Map.has_key?(metadata(identity), "anything")
    end
  end

  describe "profile_fields" do
    test "are saved, returned and read back", %{conn: conn, identity: identity} do
      body = conn |> patch(@path, %{"profile_fields" => [field(1)]}) |> json_response(200)

      assert body["profile_fields"] == [%{"name" => "name 1", "value" => "value 1"}]
      assert metadata(identity)["profile_fields"] == [field(1)]
    end

    test "are capped by tier", %{conn: conn, identity: identity} do
      cap = Hybridsocial.Premium.TierLimits.limit(identity, :profile_fields)

      conn
      |> patch(@path, %{"profile_fields" => Enum.map(1..(cap + 5), &field/1)})
      |> json_response(200)

      assert length(metadata(identity)["profile_fields"]) == cap
    end

    test "lengths are clamped", %{conn: conn, identity: identity} do
      long = %{"name" => String.duplicate("n", 500), "value" => String.duplicate("v", 5000)}

      conn |> patch(@path, %{"profile_fields" => [long]}) |> json_response(200)

      assert [%{"name" => name, "value" => value}] = metadata(identity)["profile_fields"]
      assert String.length(name) == 60
      assert String.length(value) == 280
    end

    test "malformed entries are dropped rather than crashing", %{conn: conn, identity: identity} do
      junk = [%{"name" => %{"a" => 1}, "value" => [1]}, "text", 5, %{"name" => "only"}, field(1)]

      conn |> patch(@path, %{"profile_fields" => junk}) |> json_response(200)

      assert metadata(identity)["profile_fields"] == [field(1)]
    end

    test "a request that doesn't mention them leaves them alone", %{
      conn: conn,
      identity: identity
    } do
      conn |> patch(@path, %{"profile_fields" => [field(1)]}) |> json_response(200)
      conn |> patch(@path, %{"display_name" => "Other"}) |> json_response(200)

      assert metadata(identity)["profile_fields"] == [field(1)]
    end

    test "an empty list clears them", %{conn: conn, identity: identity} do
      conn |> patch(@path, %{"profile_fields" => [field(1)]}) |> json_response(200)
      conn |> patch(@path, %{"profile_fields" => []}) |> json_response(200)

      assert metadata(identity)["profile_fields"] == []
    end
  end

  test "another server can fetch an actor that has profile fields", %{
    conn: conn,
    identity: identity
  } do
    conn |> patch(@path, %{"profile_fields" => [field(1)]}) |> json_response(200)

    actor =
      build_conn()
      |> put_req_header("accept", "application/activity+json")
      |> get("/actors/#{identity.id}")
      |> json_response(200)

    assert [%{"type" => "PropertyValue", "name" => "name 1"}] = actor["attachment"]
  end
end

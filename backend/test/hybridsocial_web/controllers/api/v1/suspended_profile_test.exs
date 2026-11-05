defmodule HybridsocialWeb.Api.V1.SuspendedProfileTest do
  use HybridsocialWeb.ConnCase

  import Ecto.Query

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Federation
  alias Hybridsocial.Repo
  alias Hybridsocial.Social
  alias Hybridsocial.Social.Posts

  defp suspended_account(handle) do
    identity = create_user(handle)
    {:ok, post} = Posts.create_post(identity.id, %{"content" => "hello"})
    {:ok, identity} = Accounts.suspend_identity(identity)
    %{identity: identity, post: post}
  end

  defp account_on_suspended_domain(handle) do
    identity = create_user(handle)
    {:ok, post} = Posts.create_post(identity.id, %{"content" => "hello"})

    {1, _} =
      Repo.update_all(from(i in Identity, where: i.id == ^identity.id),
        set: [is_local: false, ap_actor_url: "https://evil.example/users/#{handle}"]
      )

    {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)
    %{identity: Repo.get!(Identity, identity.id), post: post}
  end

  defp staff_conn(conn, handle), do: admin_conn(conn, create_admin(handle))

  describe "a regular viewer" do
    setup %{conn: conn} do
      %{viewer: auth_conn(conn, create_user("sp_viewer"))}
    end

    test "gets a 404 for the profile, by id and by handle", %{viewer: viewer} do
      %{identity: identity} = suspended_account("sp_a")

      assert viewer |> get("/api/v1/accounts/#{identity.id}") |> json_response(404)
      assert viewer |> get("/api/v1/accounts/lookup?handle=sp_a") |> json_response(404)
    end

    test "gets a 404 for a remote account on a suspended domain", %{viewer: viewer} do
      %{identity: identity} = account_on_suspended_domain("sp_b")

      assert viewer |> get("/api/v1/accounts/#{identity.id}") |> json_response(404)
    end

    test "gets no posts and no follow lists", %{viewer: viewer} do
      %{identity: identity, post: post} = suspended_account("sp_c")
      follower = create_user("sp_c_follower")
      {:ok, _} = Social.follow(follower.id, identity.id)

      assert viewer |> get("/api/v1/accounts/#{identity.id}/statuses") |> json_response(200) == []

      assert viewer |> get("/api/v1/accounts/#{identity.id}/followers") |> json_response(200) ==
               []

      assert viewer |> get("/api/v1/accounts/#{identity.id}/following") |> json_response(200) ==
               []

      assert viewer |> get("/api/v1/statuses/#{post.id}") |> json_response(404)
    end

    test "still sees accounts that aren't suspended, with no suspension field", %{viewer: viewer} do
      identity = create_user("sp_fine")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "hello"})

      body = viewer |> get("/api/v1/accounts/#{identity.id}") |> json_response(200)
      refute Map.has_key?(body, "suspension")
      assert viewer |> get("/api/v1/statuses/#{post.id}") |> json_response(200)
    end
  end

  test "an anonymous visitor gets a 404", %{conn: conn} do
    %{identity: identity, post: post} = suspended_account("sp_d")

    assert conn |> get("/api/v1/accounts/lookup?handle=sp_d") |> json_response(404)
    assert conn |> get("/api/v1/accounts/#{identity.id}") |> json_response(404)
    assert conn |> get("/api/v1/statuses/#{post.id}") |> json_response(404)
  end

  test "unsuspending restores access", %{conn: conn} do
    %{identity: identity} = suspended_account("sp_e")
    {:ok, _} = Accounts.unsuspend_identity(identity)

    assert conn |> get("/api/v1/accounts/#{identity.id}") |> json_response(200)
  end

  describe "staff" do
    test "see the profile and posts, marked as an account suspension", %{conn: conn} do
      %{identity: identity, post: post} = suspended_account("sp_f")
      staff = staff_conn(conn, "sp_staff_a")

      assert %{"suspension" => %{"source" => "account", "suspended_at" => at}} =
               staff |> get("/api/v1/accounts/lookup?handle=sp_f") |> json_response(200)

      refute is_nil(at)

      ids =
        staff
        |> get("/api/v1/accounts/#{identity.id}/statuses")
        |> json_response(200)
        |> Enum.map(& &1["id"])

      assert post.id in ids
      assert staff |> get("/api/v1/statuses/#{post.id}") |> json_response(200)
    end

    test "see a domain suspension marked as one", %{conn: conn} do
      %{identity: identity} = account_on_suspended_domain("sp_g")

      assert %{"suspension" => %{"source" => "domain"}} =
               conn
               |> staff_conn("sp_staff_b")
               |> get("/api/v1/accounts/#{identity.id}")
               |> json_response(200)
    end
  end
end

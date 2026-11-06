defmodule HybridsocialWeb.Api.V1.TrendsAccessTest do
  use HybridsocialWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Config
  alias Hybridsocial.Federation.InstancePolicy
  alias Hybridsocial.Repo
  alias Hybridsocial.Social
  alias Hybridsocial.Social.{Post, Posts}
  alias Hybridsocial.Trending

  @routes ~w(/api/v1/trends/tags /api/v1/trends/statuses /api/v1/trends/links /api/v1/trends/accounts)

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    start_supervised!(Config.Store)
    :ok
  end

  defp user(handle), do: create_user("#{handle}#{System.unique_integer([:positive])}")

  defp set_identity(identity, fields) do
    from(i in Identity, where: i.id == ^identity.id) |> Repo.update_all(set: fields)
    Repo.get!(Identity, identity.id)
  end

  defp engaged_post(author, attrs \\ %{}) do
    {:ok, post} = Posts.create_post(author.id, Map.merge(%{"content" => "hello #trendy"}, attrs))
    for _ <- 1..3, do: {:ok, _} = Posts.react(post.id, user("fan").id, "like")
    post
  end

  defp remote(identity) do
    set_identity(identity,
      is_local: false,
      ap_actor_url: "https://remote.example/users/#{identity.id}"
    )
  end

  defp ids(conn, path), do: conn |> get(path) |> json_response(200) |> Enum.map(& &1["id"])

  describe "public_timeline_access" do
    test "\"none\" refuses anonymous visitors on every route, but not members", %{conn: conn} do
      :ok = Config.set("public_timeline_access", "none")
      member = auth_conn(conn, user("member"))

      for route <- @routes do
        assert conn |> get(route) |> json_response(401)
        assert member |> get(route) |> json_response(200)
      end
    end

    test "\"all\" lets anonymous visitors in on every route", %{conn: conn} do
      for route <- @routes, do: assert(conn |> get(route) |> json_response(200))
    end

    test "\"local\" limits anonymous visitors to local content", %{conn: conn} do
      local = engaged_post(user("local"))
      far = engaged_post(remote(user("far")))
      {:ok, _} = Posts.create_post(user("two").id, %{"content" => "also #trendy"})
      :ok = Trending.compute_trending_posts()
      :ok = Trending.compute_trending_hashtags()
      :ok = Config.set("public_timeline_access", "local")

      statuses = conn |> get("/api/v1/trends/statuses") |> json_response(200) |> inspect()
      assert statuses =~ local.id
      refute statuses =~ far.id

      accounts = ids(conn, "/api/v1/trends/accounts")
      assert local.identity_id in accounts
      refute far.identity_id in accounts

      assert conn |> get("/api/v1/trends/tags") |> json_response(200) == []

      member = auth_conn(conn, user("member"))
      assert member |> get("/api/v1/trends/statuses") |> json_response(200) |> inspect() =~ far.id
      assert far.identity_id in ids(member, "/api/v1/trends/accounts")
      assert member |> get("/api/v1/trends/tags") |> json_response(200) != []
    end
  end

  describe "trending accounts leave out" do
    setup %{conn: conn} do
      %{conn: conn, path: "/api/v1/trends/accounts"}
    end

    test "an ordinary account drawing engagement is listed", %{conn: conn, path: path} do
      assert engaged_post(user("ok")).identity_id in ids(conn, path)
    end

    test "shadow-banned, silenced and suspended accounts", %{conn: conn, path: path} do
      for field <- [:is_shadow_banned, :is_silenced, :is_suspended] do
        identity = user("mod")
        engaged_post(identity)
        set_identity(identity, [{field, true}])

        refute identity.id in ids(conn, path), "#{field} should be left out"
      end
    end

    test "accounts on a silenced or suspended domain", %{conn: conn, path: path} do
      for {policy, domain} <- [{"silence", "quiet.example"}, {"suspend", "gone.example"}] do
        identity =
          user("dom")
          |> set_identity(
            is_local: false,
            ap_actor_url: "https://#{domain}/users/1#{System.unique_integer([:positive])}"
          )

        engaged_post(identity)
        assert identity.id in ids(conn, path)

        Repo.insert!(%InstancePolicy{domain: domain, policy: policy})
        refute identity.id in ids(conn, path), "#{policy} should be left out"
      end
    end

    test "accounts that opted out of discovery", %{conn: conn, path: path} do
      identity = user("opt")
      engaged_post(identity)
      set_identity(identity, discoverable: false)

      refute identity.id in ids(conn, path)
    end

    test "dormant accounts, whatever their follower count", %{conn: conn, path: path} do
      dormant = user("big")
      for _ <- 1..3, do: {:ok, _} = Social.follow(user("f").id, dormant.id)

      refute dormant.id in ids(conn, path)
    end

    test "accounts whose only engagement is on a hidden post", %{conn: conn, path: path} do
      identity = user("hid")
      post = engaged_post(identity)

      from(p in Post, where: p.id == ^post.id)
      |> Repo.update_all(set: [hidden_at: DateTime.utc_now()])

      refute identity.id in ids(conn, path)
    end

    test "someone the viewer blocked or muted, for that viewer", %{conn: conn, path: path} do
      identity = user("blk")
      engaged_post(identity)
      viewer = user("viewer")
      other = user("other")
      {:ok, _} = Social.mute(viewer.id, identity.id)

      refute identity.id in ids(auth_conn(conn, viewer), path)
      assert identity.id in ids(auth_conn(conn, other), path)
    end
  end

  test "trending posts leave out someone the viewer blocked", %{conn: conn} do
    post = engaged_post(user("author"))
    :ok = Trending.compute_trending_posts()
    viewer = user("viewer")
    {:ok, _} = Social.block(viewer.id, post.identity_id)

    refute auth_conn(conn, viewer)
           |> get("/api/v1/trends/statuses")
           |> json_response(200)
           |> inspect() =~ post.id

    assert auth_conn(conn, user("other"))
           |> get("/api/v1/trends/statuses")
           |> json_response(200)
           |> inspect() =~ post.id
  end
end

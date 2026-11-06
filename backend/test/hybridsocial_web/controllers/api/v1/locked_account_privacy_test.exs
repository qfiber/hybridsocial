defmodule HybridsocialWeb.Api.V1.LockedAccountPrivacyTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Federation.ActorSerializer
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Posts

  setup do
    locked =
      "lock#{System.unique_integer([:positive])}"
      |> create_user()
      |> Ecto.Changeset.change(is_locked: true)
      |> Repo.update!()

    {:ok, post} = Posts.create_post(locked.id, %{"content" => "marked public"})
    %{locked: locked, post: post}
  end

  defp member, do: create_user("mem#{System.unique_integer([:positive])}")

  describe "logged out" do
    test "the account can't be read by id or handle", %{conn: conn, locked: locked} do
      assert conn |> get("/api/v1/accounts/#{locked.id}") |> json_response(404)

      assert conn
             |> get("/api/v1/accounts/lookup", %{"handle" => locked.handle})
             |> json_response(404)
    end

    test "its posts can't be listed", %{conn: conn, locked: locked} do
      assert conn |> get("/api/v1/accounts/#{locked.id}/statuses") |> json_response(200) == []
    end

    test "its followers and following lists are empty", %{conn: conn, locked: locked} do
      {:ok, _} = Hybridsocial.Social.follow(member().id, locked.id)

      for path <- ["followers", "following"] do
        assert conn |> get("/api/v1/accounts/#{locked.id}/#{path}") |> json_response(200) == []
      end
    end

    test "a post marked public can't be opened", %{conn: conn, post: post} do
      assert conn |> get("/api/v1/statuses/#{post.id}") |> json_response(404)
      assert conn |> get("/api/v1/statuses/#{post.id}/context") |> json_response(404)
    end

    test "it isn't in the Trending feed", %{locked: locked, post: post} do
      fan = member()
      {:ok, _} = Posts.react(post.id, fan.id, "like")
      :ok = Hybridsocial.Trending.ExploreFeed.refresh()

      anonymous = Hybridsocial.Trending.ExploreFeed.list([])
      logged_in = Hybridsocial.Trending.ExploreFeed.list(viewer_id: fan.id)

      refute Enum.any?(anonymous, fn {p, _} -> p.identity_id == locked.id end)
      assert Enum.any?(logged_in, fn {p, _} -> p.identity_id == locked.id end)
    end

    test "a quote of its post is unavailable", %{post: post} do
      quoter = member()
      {:ok, outer} = Posts.create_post(quoter.id, %{"content" => "look", "quote_id" => post.id})

      serialized =
        Hybridsocial.Social.Post
        |> Repo.get!(outer.id)
        |> Repo.preload([:identity, :quote])
        |> HybridsocialWeb.Serializers.PostSerializer.serialize([])

      assert serialized.quote == nil
      assert serialized.quote_unavailable == true
    end
  end

  describe "logged in, which is unchanged" do
    test "any member can still read the account and public post",
         %{conn: conn, locked: locked, post: post} do
      conn = auth_conn(conn, member())

      assert conn |> get("/api/v1/accounts/#{locked.id}") |> json_response(200)

      assert [%{"id" => id}] =
               conn |> get("/api/v1/accounts/#{locked.id}/statuses") |> json_response(200)

      assert id == post.id
      assert conn |> get("/api/v1/statuses/#{post.id}") |> json_response(200)
    end

    test "the account can read itself", %{conn: conn, locked: locked} do
      assert conn
             |> auth_conn(locked)
             |> get("/api/v1/accounts/#{locked.id}")
             |> json_response(200)
    end
  end

  describe "federation, which is unchanged" do
    test "other servers can still fetch the actor", %{conn: conn, locked: locked} do
      actor =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/actors/#{locked.id}")
        |> json_response(200)

      assert actor["manuallyApprovesFollowers"] == true
      assert ActorSerializer.to_ap(locked)["id"] == actor["id"]
    end
  end
end

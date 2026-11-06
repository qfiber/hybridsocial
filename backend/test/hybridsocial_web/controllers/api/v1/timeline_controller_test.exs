defmodule HybridsocialWeb.Api.V1.TimelineControllerTest do
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Post, Follow}

  setup do
    try do
      Hybridsocial.Cache.flush_pattern("feed:*")
    rescue
      _ -> :ok
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_post(identity, attrs) do
    defaults = %{
      identity_id: identity.id,
      content: "Test post by #{identity.handle}",
      visibility: "public",
      post_type: "text"
    }

    # create_changeset never casts published_at (Posts.create_post stamps
    # it after), so a raw insert leaves it nil and the post is filtered out
    # of every timeline as unpublished. Stamp it here to mirror a real post.
    now = DateTime.utc_now()

    %Post{}
    |> Post.create_changeset(Map.merge(defaults, attrs))
    |> Ecto.Changeset.put_change(:published_at, Map.get(attrs, :published_at, now))
    |> Ecto.Changeset.put_change(:last_activity_at, Map.get(attrs, :last_activity_at, now))
    |> Repo.insert!()
  end

  defp create_follow(follower, followee) do
    %Follow{}
    |> Follow.changeset(%{
      follower_id: follower.id,
      followee_id: followee.id,
      status: :accepted
    })
    |> Repo.insert!()
  end

  # Delegate to the shared fixture so the access token gets a live
  # oauth_tokens row — the auth plug now enforces revocation and 401s a
  # bare JWT with no session row.
  defp authenticate(conn, identity), do: auth_conn(conn, identity)

  # ---------------------------------------------------------------------------
  # Home Timeline
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/timelines/home" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/timelines/home")
      assert json_response(conn, 401)
    end

    test "returns posts from followed accounts", %{conn: conn} do
      alice = create_user("tl_alice", "tl_alice@example.com")
      bob = create_user("tl_bob", "tl_bob@example.com")
      create_follow(alice, bob)
      post = create_post(bob, %{content: "Bob's post"})

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/timelines/home")

      response = json_response(conn, 200)
      assert is_list(response)

      assert Enum.any?(response, fn entry ->
               entry["id"] == post.id or
                 (entry["post"] && entry["post"]["id"] == post.id)
             end)
    end

    test "supports limit param", %{conn: conn} do
      alice = create_user("tl_alice_lim", "tl_alice_lim@example.com")
      bob = create_user("tl_bob_lim", "tl_bob_lim@example.com")
      create_follow(alice, bob)

      for i <- 1..5 do
        create_post(bob, %{content: "Post #{i}"})
      end

      conn =
        conn
        |> authenticate(alice)
        |> get("/api/v1/timelines/home", %{"limit" => "2"})

      response = json_response(conn, 200)
      assert length(response) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Public Timeline
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/timelines/public" do
    test "returns public posts without authentication", %{conn: conn} do
      alice = create_user("pub_alice", "pub_alice@example.com")
      post = create_post(alice, %{content: "Public post", visibility: "public"})

      conn = get(conn, "/api/v1/timelines/public")

      response = json_response(conn, 200)
      assert is_list(response)
      assert Enum.any?(response, fn p -> p["id"] == post.id end)
    end

    test "excludes non-public posts", %{conn: conn} do
      alice = create_user("pub_alice2", "pub_alice2@example.com")
      _private = create_post(alice, %{content: "Private", visibility: "followers"})

      conn = get(conn, "/api/v1/timelines/public")

      response = json_response(conn, 200)
      refute Enum.any?(response, fn p -> p["id"] == _private.id end)
    end

    test "excludes replies by default", %{conn: conn} do
      alice = create_user("pub_alice3", "pub_alice3@example.com")
      parent = create_post(alice, %{content: "Parent"})

      reply =
        create_post(alice, %{
          content: "Reply",
          parent_id: parent.id,
          root_id: parent.id
        })

      conn = get(conn, "/api/v1/timelines/public")

      response = json_response(conn, 200)
      ids = Enum.map(response, & &1["id"])
      assert parent.id in ids
      refute reply.id in ids
    end

    test "includes replies when requested", %{conn: conn} do
      alice = create_user("pub_alice4", "pub_alice4@example.com")
      parent = create_post(alice, %{content: "Parent"})

      reply =
        create_post(alice, %{
          content: "Reply",
          parent_id: parent.id,
          root_id: parent.id
        })

      conn = get(conn, "/api/v1/timelines/public", %{"include_replies" => "true"})

      response = json_response(conn, 200)
      ids = Enum.map(response, & &1["id"])
      assert parent.id in ids
      assert reply.id in ids
    end

    test "returns Link headers for pagination", %{conn: conn} do
      alice = create_user("pub_alice5", "pub_alice5@example.com")
      create_post(alice, %{content: "Post 1"})
      create_post(alice, %{content: "Post 2"})

      conn = get(conn, "/api/v1/timelines/public")

      assert get_resp_header(conn, "link") != []
    end
  end

  # ---------------------------------------------------------------------------
  # Global Timeline (prewarmed snapshot + per-viewer overlay)
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/timelines/global" do
    test "returns public posts without authentication", %{conn: conn} do
      alice = create_user("glob_alice", "glob_alice@example.com")
      post = create_post(alice, %{content: "Global post", visibility: "public"})

      conn = get(conn, "/api/v1/timelines/global")

      response = json_response(conn, 200)
      assert is_list(response)
      assert Enum.any?(response, fn p -> p["id"] == post.id end)
    end

    test "excludes non-public posts", %{conn: conn} do
      alice = create_user("glob_alice2", "glob_alice2@example.com")
      private = create_post(alice, %{content: "Private", visibility: "followers"})

      conn = get(conn, "/api/v1/timelines/global")

      response = json_response(conn, 200)
      refute Enum.any?(response, fn p -> p["id"] == private.id end)
    end

    test "serves the first page from a cached snapshot", %{conn: conn} do
      alice = create_user("glob_alice3", "glob_alice3@example.com")
      first = create_post(alice, %{content: "First"})

      # First request computes and caches the snapshot.
      resp1 = get(conn, "/api/v1/timelines/global") |> json_response(200)
      assert Enum.any?(resp1, &(&1["id"] == first.id))

      # A post created afterwards must NOT appear until the snapshot is
      # refreshed — proving the response came from the warm snapshot, not
      # a fresh query.
      second = create_post(alice, %{content: "Second"})
      resp2 = build_conn() |> get("/api/v1/timelines/global") |> json_response(200)
      refute Enum.any?(resp2, &(&1["id"] == second.id))
    end

    test "overlays the viewer's own reaction and bookmark onto the snapshot",
         %{conn: conn} do
      author = create_user("glob_author", "glob_author@example.com")
      viewer = create_user("glob_viewer", "glob_viewer@example.com")
      post = create_post(author, %{content: "React to me"})

      {:ok, _} = Hybridsocial.Social.Posts.react(post.id, viewer.id, "like")
      {:ok, _} = Hybridsocial.Social.Bookmarks.bookmark(viewer.id, post.id)

      response =
        conn
        |> authenticate(viewer)
        |> get("/api/v1/timelines/global")
        |> json_response(200)

      entry = Enum.find(response, &(&1["id"] == post.id))
      assert entry["current_user_reaction"] == "like"
      assert entry["is_bookmarked"] == true
      assert Enum.any?(entry["reactions"], &(&1["name"] == "like" and &1["me"] == true))
    end

    test "anonymous viewer sees no personal reaction state", %{conn: conn} do
      author = create_user("glob_author2", "glob_author2@example.com")
      reactor = create_user("glob_reactor2", "glob_reactor2@example.com")
      post = create_post(author, %{content: "Popular"})
      {:ok, _} = Hybridsocial.Social.Posts.react(post.id, reactor.id, "like")

      response = get(conn, "/api/v1/timelines/global") |> json_response(200)
      entry = Enum.find(response, &(&1["id"] == post.id))

      assert entry["current_user_reaction"] == nil
      assert entry["is_bookmarked"] == false
      # Count is viewer-independent and still reflects the reaction.
      assert Enum.any?(entry["reactions"], &(&1["name"] == "like" and &1["me"] == false))
    end
  end

  # ---------------------------------------------------------------------------
  # Hashtag Timeline
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/timelines/tag/:hashtag" do
    test "returns posts matching the hashtag", %{conn: conn} do
      alice = create_user("tag_alice", "tag_alice@example.com")
      tagged = create_post(alice, %{content: "Hello #phoenix world"})
      _untagged = create_post(alice, %{content: "Hello world"})

      conn = get(conn, "/api/v1/timelines/tag/phoenix")

      response = json_response(conn, 200)
      ids = Enum.map(response, & &1["id"])

      assert tagged.id in ids
      refute _untagged.id in ids
    end

    test "only returns public posts", %{conn: conn} do
      alice = create_user("tag_alice2", "tag_alice2@example.com")

      _private =
        create_post(alice, %{content: "#phoenix post", visibility: "followers"})

      conn = get(conn, "/api/v1/timelines/tag/phoenix")

      response = json_response(conn, 200)
      assert response == []
    end

    test "overlays the viewer's own reaction onto the snapshot", %{conn: conn} do
      author = create_user("tag_author", "tag_author@example.com")
      viewer = create_user("tag_viewer", "tag_viewer@example.com")
      post = create_post(author, %{content: "Tagged #elixir post"})
      {:ok, _} = Hybridsocial.Social.Posts.react(post.id, viewer.id, "love")

      response =
        conn
        |> authenticate(viewer)
        |> get("/api/v1/timelines/tag/elixir")
        |> json_response(200)

      entry = Enum.find(response, &(&1["id"] == post.id))
      assert entry["current_user_reaction"] == "love"
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/timelines/trending
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/timelines/trending" do
    alias Hybridsocial.Accounts.Identity
    alias Hybridsocial.Social.Posts
    alias Hybridsocial.Trending.ExploreFeed

    defp engaged_post(author, content, count) do
      post = create_post(author, %{content: content})

      for n <- 1..count do
        {:ok, _} =
          Posts.react(
            post.id,
            create_user("tf#{n}_#{System.unique_integer([:positive])}").id,
            "like"
          )
      end

      post
    end

    defp make_remote(identity) do
      identity
      |> Ecto.Changeset.change(
        is_local: false,
        ap_actor_url: "https://remote.example/users/#{identity.id}"
      )
      |> Repo.update!()

      Repo.get!(Identity, identity.id)
    end

    defp put_access(level) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      start_supervised!(Hybridsocial.Config.Store)
      :ok = Hybridsocial.Config.set("public_timeline_access", level)
    end

    test "returns the blended feed with the viewer's follow state", %{conn: conn} do
      viewer = create_user("tviewer")
      followed = create_user("tfollowed")
      stranger = create_user("tstranger")
      create_follow(viewer, followed)

      followed_post = engaged_post(followed, "followed", 1)
      stranger_post = engaged_post(stranger, "stranger", 1)
      own_post = engaged_post(viewer, "own", 1)
      :ok = ExploreFeed.refresh()

      response =
        conn |> auth_conn(viewer) |> get("/api/v1/timelines/trending") |> json_response(200)

      by_id = Map.new(response, &{&1["id"], &1})

      assert by_id[followed_post.id]["viewer_follows_author"] == true
      assert by_id[own_post.id]["viewer_follows_author"] == true
      assert by_id[stranger_post.id]["viewer_follows_author"] == false
      assert Map.has_key?(by_id[stranger_post.id], "trending_reason")
    end

    test "an anonymous viewer gets no follow state", %{conn: conn} do
      post = engaged_post(create_user("tanon"), "anon", 1)
      :ok = ExploreFeed.refresh()

      [entry] = conn |> get("/api/v1/timelines/trending") |> json_response(200)

      assert entry["id"] == post.id
      assert entry["viewer_follows_author"] == nil
    end

    test "pages by the last post's id", %{conn: conn} do
      posts = for n <- 1..3, do: engaged_post(create_user("tpage#{n}"), "p#{n}", 1)
      :ok = ExploreFeed.refresh()

      first = conn |> get("/api/v1/timelines/trending?limit=2") |> json_response(200)
      assert length(first) == 2

      second =
        conn
        |> get("/api/v1/timelines/trending?limit=2&max_id=#{List.last(first)["id"]}")
        |> json_response(200)

      assert length(second) == 1

      assert Enum.sort(Enum.map(first ++ second, & &1["id"])) ==
               Enum.sort(Enum.map(posts, & &1.id))
    end

    test "a page size does not leak through the first-page cache", %{conn: conn} do
      for n <- 1..3, do: engaged_post(create_user("tcache#{n}"), "p#{n}", 1)
      :ok = ExploreFeed.refresh()

      assert [_] = conn |> get("/api/v1/timelines/trending?limit=1") |> json_response(200)
      assert length(conn |> get("/api/v1/timelines/trending") |> json_response(200)) == 3
    end

    test "under \"local\" access an anonymous viewer gets only local posts", %{conn: conn} do
      local = engaged_post(create_user("tlocal"), "local", 1)
      remote = engaged_post(make_remote(create_user("tremote")), "remote", 3)
      :ok = ExploreFeed.refresh()
      put_access("local")

      anon =
        conn
        |> get("/api/v1/timelines/trending")
        |> json_response(200)
        |> Enum.map(& &1["id"])

      assert local.id in anon
      refute remote.id in anon

      member =
        conn
        |> auth_conn(create_user("tmember"))
        |> get("/api/v1/timelines/trending")
        |> json_response(200)
        |> Enum.map(& &1["id"])

      assert remote.id in member
    end

    test "under \"none\" access an anonymous viewer is refused", %{conn: conn} do
      put_access("none")
      assert conn |> get("/api/v1/timelines/trending") |> json_response(401)
    end
  end

  describe "GET /api/v1/timelines/public access" do
    test "local=false needs the same access as Global", %{conn: conn} do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      start_supervised!(Hybridsocial.Config.Store)
      :ok = Hybridsocial.Config.set("public_timeline_access", "local")

      assert conn |> get("/api/v1/timelines/public?local=false") |> json_response(401)
      assert conn |> get("/api/v1/timelines/public") |> json_response(200)
    end
  end
end

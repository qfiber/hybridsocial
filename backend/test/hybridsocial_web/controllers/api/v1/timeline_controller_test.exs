defmodule HybridsocialWeb.Api.V1.TimelineControllerTest do
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Post, Follow}
  alias Hybridsocial.Auth.Token

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

  defp create_post(identity, attrs) do
    defaults = %{
      identity_id: identity.id,
      content: "Test post by #{identity.handle}",
      visibility: "public",
      post_type: "text"
    }

    %Post{}
    |> Post.create_changeset(Map.merge(defaults, attrs))
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

  defp authenticate(conn, identity) do
    {:ok, access_token, _claims} = Token.generate_access_token(identity.id)

    conn
    |> put_req_header("authorization", "Bearer #{access_token}")
  end

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
        (entry["id"] == post.id) or
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
  end
end

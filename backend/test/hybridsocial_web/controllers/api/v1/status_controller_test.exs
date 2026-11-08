defmodule HybridsocialWeb.Api.V1.StatusControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Hybridsocial.Social.Posts

  defp login(conn, email) do
    {:ok, tokens} = Hybridsocial.Auth.login(email, "password1234567890")
    put_req_header(conn, "authorization", "Bearer #{tokens.access_token}")
  end

  defp setup_user(%{conn: conn}) do
    identity = create_user("testuser", "testuser@test.com")
    conn = login(conn, "testuser@test.com")
    %{conn: conn, identity: identity}
  end

  describe "POST /api/v1/statuses" do
    setup :setup_user

    test "creates a post", %{conn: conn} do
      conn =
        post(conn, "/api/v1/statuses", %{
          "content" => "Hello world!",
          "visibility" => "public"
        })

      response = json_response(conn, 201)
      assert response["content"] == "Hello world!"
      assert response["visibility"] == "public"
      assert response["account"]["handle"] == "testuser"
      assert response["id"] != nil
    end

    test "returns errors for invalid post", %{conn: conn} do
      conn = post(conn, "/api/v1/statuses", %{"visibility" => "public"})
      response = json_response(conn, 422)
      assert response["error"] == "validation.failed"
    end

    test "posting to a page the user can edit is authored as the page",
         %{conn: conn, identity: identity} do
      {:ok, page} =
        Hybridsocial.Pages.create_page(identity.id, %{
          "handle" => "mypage",
          "display_name" => "My Page"
        })

      conn =
        post(conn, "/api/v1/statuses", %{
          "content" => "From the page",
          "visibility" => "public",
          "page_id" => page.id
        })

      response = json_response(conn, 201)
      # Authored as the page, not the logged-in user.
      assert response["account"]["handle"] == "mypage"
      assert response["account"]["handle"] != "testuser"
    end

    test "posting to a page the user cannot edit is forbidden", %{conn: conn} do
      other = create_user("pageowner", "pageowner@test.com")

      {:ok, page} =
        Hybridsocial.Pages.create_page(other.id, %{
          "handle" => "otherspage",
          "display_name" => "Someone Else's Page"
        })

      conn =
        post(conn, "/api/v1/statuses", %{
          "content" => "I should not be able to post here",
          "visibility" => "public",
          "page_id" => page.id
        })

      assert json_response(conn, 403)["error"] == "page.forbidden"
    end

    test "requires authentication", %{conn: _conn} do
      conn = build_conn()
      conn = post(conn, "/api/v1/statuses", %{"content" => "Hello"})
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/statuses/:id" do
    setup :setup_user

    test "shows a post", %{conn: conn, identity: identity} do
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Show me"})

      conn = get(conn, "/api/v1/statuses/#{post.id}")
      response = json_response(conn, 200)
      assert response["content"] == "Show me"
      assert response["account"]["handle"] == "testuser"
    end

    test "returns 404 for missing post", %{conn: conn} do
      fake_id = Ecto.UUID.generate()
      conn = get(conn, "/api/v1/statuses/#{fake_id}")
      assert json_response(conn, 404)["error"] == "status.not_found"
    end
  end

  describe "POST /api/v1/statuses/by_ids" do
    setup :setup_user

    test "returns posts matching the given IDs", %{conn: conn, identity: identity} do
      {:ok, a} = Posts.create_post(identity.id, %{"content" => "A"})
      {:ok, b} = Posts.create_post(identity.id, %{"content" => "B"})
      {:ok, _unwanted} = Posts.create_post(identity.id, %{"content" => "not requested"})

      conn = post(conn, "/api/v1/statuses/by_ids", %{"ids" => [a.id, b.id]})
      response = json_response(conn, 200)

      assert is_list(response)
      assert length(response) == 2
      ids = Enum.map(response, & &1["id"])
      assert a.id in ids
      assert b.id in ids
    end

    test "silently skips unknown IDs", %{conn: conn, identity: identity} do
      {:ok, real} = Posts.create_post(identity.id, %{"content" => "real"})
      fake_id = Ecto.UUID.generate()

      conn = post(conn, "/api/v1/statuses/by_ids", %{"ids" => [real.id, fake_id]})
      response = json_response(conn, 200)

      assert length(response) == 1
      assert hd(response)["id"] == real.id
    end

    test "returns [] for an empty list", %{conn: conn} do
      conn = post(conn, "/api/v1/statuses/by_ids", %{"ids" => []})
      assert json_response(conn, 200) == []
    end

    test "returns [] when ids key is missing or malformed", %{conn: conn} do
      conn = post(conn, "/api/v1/statuses/by_ids", %{})
      assert json_response(conn, 200) == []

      conn2 = post(build_conn(), "/api/v1/statuses/by_ids", %{"ids" => "not-a-list"})
      assert json_response(conn2, 200) == []
    end

    test "caps response at 100 posts per request", %{conn: conn, identity: identity} do
      # Intersperse 101 real post IDs to ensure the cap applies regardless
      # of whether the client repeats or pads — we just need to prove the
      # endpoint doesn't blow up on a long list.
      ids =
        Enum.map(1..101, fn i ->
          {:ok, p} = Posts.create_post(identity.id, %{"content" => "post #{i}"})
          p.id
        end)

      conn = post(conn, "/api/v1/statuses/by_ids", %{"ids" => ids})
      response = json_response(conn, 200)
      assert length(response) <= 100
    end
  end

  describe "PUT /api/v1/statuses/:id" do
    setup :setup_user

    test "edits own post", %{conn: conn, identity: identity} do
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Original"})

      conn = put(conn, "/api/v1/statuses/#{post.id}", %{"content" => "Edited"})
      response = json_response(conn, 200)
      assert response["content"] == "Edited"
      assert response["edited_at"] != nil
    end

    test "rejects editing another user's post", %{conn: conn} do
      other = create_user("other", "other@test.com")
      {:ok, post} = Posts.create_post(other.id, %{"content" => "Not yours"})

      conn = put(conn, "/api/v1/statuses/#{post.id}", %{"content" => "Hacked"})
      assert json_response(conn, 403)["error"] == "status.forbidden"
    end
  end

  describe "DELETE /api/v1/statuses/:id" do
    setup :setup_user

    test "deletes own post", %{conn: conn, identity: identity} do
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Delete me"})

      conn = delete(conn, "/api/v1/statuses/#{post.id}")
      assert json_response(conn, 200)["message"] == "status.deleted"
    end

    test "rejects deleting another user's post", %{conn: conn} do
      other = create_user("other2", "other2@test.com")
      {:ok, post} = Posts.create_post(other.id, %{"content" => "Not yours"})

      conn = delete(conn, "/api/v1/statuses/#{post.id}")
      assert json_response(conn, 403)["error"] == "status.forbidden"
    end
  end

  describe "GET /api/v1/statuses/:id/history" do
    setup :setup_user

    test "returns edit history", %{conn: conn, identity: identity} do
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "V1"})
      {:ok, _} = Posts.edit_post(post.id, identity.id, %{"content" => "V2"})

      conn = get(conn, "/api/v1/statuses/#{post.id}/history")
      response = json_response(conn, 200)
      assert length(response) == 1
      assert hd(response)["content"] == "V1"
    end
  end

  describe "POST /api/v1/statuses/:id/react" do
    setup :setup_user

    test "adds a reaction", %{conn: conn, identity: identity} do
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "React to me"})

      conn = post(conn, "/api/v1/statuses/#{post.id}/react", %{"type" => "love"})
      response = json_response(conn, 200)
      assert response["type"] == "love"
    end
  end

  describe "DELETE /api/v1/statuses/:id/react" do
    setup :setup_user

    test "removes a reaction", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Unreact me"})
      {:ok, _} = Posts.react(post_record.id, identity.id, "like")

      conn = delete(conn, "/api/v1/statuses/#{post_record.id}/react")
      assert json_response(conn, 200)["message"] == "reaction.removed"
    end
  end

  describe "POST /api/v1/statuses/:id/boost" do
    setup :setup_user

    test "boosts a post", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Boost me"})

      conn = post(conn, "/api/v1/statuses/#{post_record.id}/boost")
      response = json_response(conn, 200)
      assert response["id"] == post_record.id
    end
  end

  describe "DELETE /api/v1/statuses/:id/boost" do
    setup :setup_user

    test "removes a boost", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Unboost me"})
      {:ok, _} = Posts.boost(post_record.id, identity.id)

      conn = delete(conn, "/api/v1/statuses/#{post_record.id}/boost")
      assert json_response(conn, 200)["message"] == "boost.removed"
    end
  end

  describe "GET /api/v1/statuses/:id/context" do
    setup :setup_user

    test "returns thread context", %{conn: conn, identity: identity} do
      {:ok, root} = Posts.create_post(identity.id, %{"content" => "Root"})

      {:ok, reply} =
        Posts.create_post(identity.id, %{
          "content" => "Reply",
          "parent_id" => root.id,
          "root_id" => root.id
        })

      conn = get(conn, "/api/v1/statuses/#{reply.id}/context")
      response = json_response(conn, 200)
      assert is_list(response["ancestors"])
      assert is_list(response["descendants"])
    end
  end

  describe "POST /api/v1/statuses/:id/pin" do
    setup :setup_user

    test "pins a post", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Pin me"})

      conn = post(conn, "/api/v1/statuses/#{post_record.id}/pin")
      response = json_response(conn, 200)
      assert response["is_pinned"] == true
    end
  end

  describe "DELETE /api/v1/statuses/:id/pin" do
    setup :setup_user

    test "unpins a post", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Unpin me"})
      {:ok, _} = Posts.pin_post(post_record.id, identity.id)

      conn = delete(conn, "/api/v1/statuses/#{post_record.id}/pin")
      response = json_response(conn, 200)
      assert response["is_pinned"] == false
    end
  end

  describe "posting rate limits" do
    alias Hybridsocial.Accounts.Identity

    setup do
      Application.put_env(:hybridsocial, :rate_limiting_enabled, true)
      on_exit(fn -> Application.put_env(:hybridsocial, :rate_limiting_enabled, false) end)
      :ok
    end

    defp limited_user(limits) do
      "lim#{System.unique_integer([:positive])}"
      |> create_user()
      |> Ecto.Changeset.change(post_limits: limits)
      |> Hybridsocial.Repo.update!()
    end

    test "past the limit a post is refused with a 429 that says when to retry", %{conn: conn} do
      identity = limited_user(%{"per_minute" => 1})
      conn = auth_conn(conn, identity)

      assert conn |> post("/api/v1/statuses", %{"content" => "one"}) |> json_response(201)

      refused = post(conn, "/api/v1/statuses", %{"content" => "two"})
      body = json_response(refused, 429)

      assert body["error"] == "limits.post_rate_limit"
      assert body["window"] == "minute"
      assert body["limit"] == 1
      assert [retry_after] = get_resp_header(refused, "retry-after")
      assert String.to_integer(retry_after) == body["retry_after"]
    end

    test "a refused post is not created", %{conn: conn} do
      identity = limited_user(%{"per_minute" => 0, "per_hour" => 1})
      conn = auth_conn(conn, identity)

      post(conn, "/api/v1/statuses", %{"content" => "kept"})
      assert conn |> post("/api/v1/statuses", %{"content" => "refused"}) |> json_response(429)

      count =
        Hybridsocial.Repo.aggregate(
          from(p in Hybridsocial.Social.Post, where: p.identity_id == ^identity.id),
          :count
        )

      assert count == 1
    end

    test "deleting a post does not free up the allowance", %{conn: conn} do
      identity = limited_user(%{"per_minute" => 1})
      conn = auth_conn(conn, identity)

      %{"id" => id} =
        conn |> post("/api/v1/statuses", %{"content" => "one"}) |> json_response(201)

      delete(conn, "/api/v1/statuses/#{id}")

      assert conn |> post("/api/v1/statuses", %{"content" => "two"}) |> json_response(429)
    end

    test "replies are not limited and don't use up the allowance", %{conn: conn} do
      identity = limited_user(%{"per_minute" => 1})
      conn = auth_conn(conn, identity)

      %{"id" => id} =
        conn |> post("/api/v1/statuses", %{"content" => "post"}) |> json_response(201)

      # Past the limit for posts, replies still go through, in both spellings.
      for n <- 1..3 do
        assert conn
               |> post("/api/v1/statuses", %{"content" => "reply #{n}", "parent_id" => id})
               |> json_response(201)
      end

      assert conn
             |> post("/api/v1/statuses", %{"content" => "masto", "in_reply_to_id" => id})
             |> json_response(201)

      assert conn |> post("/api/v1/statuses", %{"content" => "post 2"}) |> json_response(429)
    end

    test "a reply to a post that doesn't exist can't slip a post past the limit",
         %{conn: conn} do
      identity = limited_user(%{"per_minute" => 1})
      conn = auth_conn(conn, identity)

      assert conn |> post("/api/v1/statuses", %{"content" => "post"}) |> json_response(201)

      conn
      |> post("/api/v1/statuses", %{"content" => "sneaky", "parent_id" => Ecto.UUID.generate()})

      top_level =
        Hybridsocial.Repo.aggregate(
          from(p in Hybridsocial.Social.Post,
            where:
              p.identity_id == ^identity.id and is_nil(p.parent_id) and is_nil(p.parent_ap_id)
          ),
          :count
        )

      assert top_level == 1
    end

    test "scheduling a post uses the allowance too", %{conn: conn} do
      identity = limited_user(%{"per_minute" => 1})
      conn = auth_conn(conn, identity)
      at = DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.to_iso8601()
      params = %{"content" => "later", "scheduled_at" => at}

      assert conn |> post("/api/v1/statuses/schedule", params) |> json_response(201)
      assert conn |> post("/api/v1/statuses/schedule", params) |> json_response(429)
    end

    test "a user can't lift their own limit through their profile", %{conn: conn} do
      identity = limited_user(%{"per_minute" => 1})
      conn = auth_conn(conn, identity)

      patch(conn, "/api/v1/accounts/update_credentials", %{
        "post_limits" => %{"per_minute" => 0},
        "metadata" => %{"posts_per_hour" => 0, "post_limits" => %{"per_minute" => 0}}
      })

      assert Hybridsocial.Repo.get!(Identity, identity.id).post_limits == %{"per_minute" => 1}

      assert conn |> post("/api/v1/statuses", %{"content" => "one"}) |> json_response(201)
      assert conn |> post("/api/v1/statuses", %{"content" => "two"}) |> json_response(429)
    end
  end
end

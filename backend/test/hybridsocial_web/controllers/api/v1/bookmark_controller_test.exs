defmodule HybridsocialWeb.Api.V1.BookmarkControllerTest do
  use HybridsocialWeb.ConnCase, async: true

  alias Hybridsocial.Social.Posts

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  defp login(conn, email) do
    {:ok, tokens} = Hybridsocial.Auth.login(email, "password123")
    put_req_header(conn, "authorization", "Bearer #{tokens.access_token}")
  end

  defp setup_user(%{conn: conn}) do
    identity = create_user("bmtestuser", "bmtestuser@test.com")
    conn = login(conn, "bmtestuser@test.com")
    %{conn: conn, identity: identity}
  end

  describe "POST /api/v1/statuses/:id/bookmark" do
    setup :setup_user

    test "bookmarks a post", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Bookmark me"})

      conn = post(conn, "/api/v1/statuses/#{post_record.id}/bookmark")
      response = json_response(conn, 200)
      assert response["post_id"] == post_record.id
    end

    test "returns error for duplicate bookmark", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Bookmark me twice"})

      post(conn, "/api/v1/statuses/#{post_record.id}/bookmark")
      conn = post(conn, "/api/v1/statuses/#{post_record.id}/bookmark")
      assert json_response(conn, 422)["error"] == "validation.failed"
    end
  end

  describe "DELETE /api/v1/statuses/:id/bookmark" do
    setup :setup_user

    test "removes a bookmark", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Unbookmark me"})

      post(conn, "/api/v1/statuses/#{post_record.id}/bookmark")
      conn = delete(conn, "/api/v1/statuses/#{post_record.id}/bookmark")
      assert json_response(conn, 200)["message"] == "bookmark.removed"
    end

    test "returns error when bookmark does not exist", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Not bookmarked"})

      conn = delete(conn, "/api/v1/statuses/#{post_record.id}/bookmark")
      assert json_response(conn, 404)["error"] == "bookmark.not_found"
    end
  end

  describe "GET /api/v1/bookmarks" do
    setup :setup_user

    test "lists bookmarked posts", %{conn: conn, identity: identity} do
      {:ok, post_record} = Posts.create_post(identity.id, %{"content" => "Bookmarked post"})
      post(conn, "/api/v1/statuses/#{post_record.id}/bookmark")

      conn = get(conn, "/api/v1/bookmarks")
      response = json_response(conn, 200)
      assert is_list(response["posts"])
      assert length(response["posts"]) == 1
      assert hd(response["posts"])["content"] == "Bookmarked post"
    end

    test "returns empty list when no bookmarks", %{conn: conn} do
      conn = get(conn, "/api/v1/bookmarks")
      response = json_response(conn, 200)
      assert response["posts"] == []
    end
  end
end

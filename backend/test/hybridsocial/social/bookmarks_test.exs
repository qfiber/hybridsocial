defmodule Hybridsocial.Social.BookmarksTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Social.{Bookmarks, Posts}

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

  describe "bookmark/2" do
    test "creates a bookmark" do
      identity = create_user("bm_user1", "bm1@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Bookmark me"})

      assert {:ok, bookmark} = Bookmarks.bookmark(identity.id, post.id)
      assert bookmark.identity_id == identity.id
      assert bookmark.post_id == post.id
    end

    test "prevents duplicate bookmarks" do
      identity = create_user("bm_user2", "bm2@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Bookmark me"})

      assert {:ok, _} = Bookmarks.bookmark(identity.id, post.id)
      assert {:error, _} = Bookmarks.bookmark(identity.id, post.id)
    end
  end

  describe "unbookmark/2" do
    test "removes a bookmark" do
      identity = create_user("bm_user3", "bm3@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Unbookmark me"})

      {:ok, _} = Bookmarks.bookmark(identity.id, post.id)
      assert {:ok, _} = Bookmarks.unbookmark(identity.id, post.id)
      refute Bookmarks.bookmarked?(identity.id, post.id)
    end

    test "returns error when bookmark does not exist" do
      identity = create_user("bm_user4", "bm4@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Not bookmarked"})

      assert {:error, :not_found} = Bookmarks.unbookmark(identity.id, post.id)
    end
  end

  describe "bookmarked?/2" do
    test "returns true when bookmarked" do
      identity = create_user("bm_user5", "bm5@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Check bookmark"})

      {:ok, _} = Bookmarks.bookmark(identity.id, post.id)
      assert Bookmarks.bookmarked?(identity.id, post.id)
    end

    test "returns false when not bookmarked" do
      identity = create_user("bm_user6", "bm6@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Not bookmarked"})

      refute Bookmarks.bookmarked?(identity.id, post.id)
    end
  end

  describe "list_bookmarks/2" do
    test "returns paginated bookmarks with preloaded posts" do
      identity = create_user("bm_user7", "bm7@test.com")

      for i <- 1..5 do
        {:ok, post} = Posts.create_post(identity.id, %{"content" => "Post #{i}"})
        Bookmarks.bookmark(identity.id, post.id)
      end

      result = Bookmarks.list_bookmarks(identity.id, limit: 3)
      assert length(result.bookmarks) == 3
      assert result.next_cursor != nil

      # Each bookmark should have a preloaded post
      Enum.each(result.bookmarks, fn bookmark ->
        assert bookmark.post != nil
        assert bookmark.post.content != nil
      end)

      result2 = Bookmarks.list_bookmarks(identity.id, limit: 3, cursor: result.next_cursor)
      assert length(result2.bookmarks) == 2
    end
  end
end

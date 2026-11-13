defmodule Hybridsocial.Social.PostExpiryTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Post, Posts}

  describe "create_post/3 with expires_in" do
    test "sets expires_at that many seconds after publish" do
      identity = create_user("timed", "timed@test.com")

      {:ok, post} =
        Posts.create_post(identity.id, %{"content" => "gone soon", "expires_in" => "3600"})

      assert DateTime.diff(post.expires_at, post.published_at) == 3600
    end

    test "leaves expires_at nil without a timer" do
      identity = create_user("untimed", "untimed@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "stays"})
      assert post.expires_at == nil
    end

    test "starts a scheduled post's clock at its scheduled time" do
      identity = create_user("schedtimed", "schedtimed@test.com")
      scheduled_at = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "later",
          "scheduled_at" => DateTime.to_iso8601(scheduled_at),
          "expires_in" => 600
        })

      assert DateTime.diff(post.expires_at, scheduled_at) == 600
    end

    test "rejects a lifetime outside the instance bounds" do
      identity = create_user("badtimer", "badtimer@test.com")
      %{min: min, max: max} = Posts.post_expiry_bounds()

      for value <- [min - 1, max + 1, "soon", -5] do
        assert {:error, :invalid_expires_in, %{min: ^min, max: ^max}} =
                 Posts.create_post(identity.id, %{"content" => "x", "expires_in" => value})
      end

      assert Repo.aggregate(Post, :count) == 0
    end
  end

  describe "delete_expired_posts/2" do
    test "deletes only posts whose timer has run out" do
      identity = create_user("sweeper", "sweeper@test.com")
      {:ok, expired} = Posts.create_post(identity.id, %{"content" => "a", "expires_in" => 300})
      {:ok, pending} = Posts.create_post(identity.id, %{"content" => "b", "expires_in" => 3600})
      {:ok, plain} = Posts.create_post(identity.id, %{"content" => "c"})

      later = DateTime.add(DateTime.utc_now(), 600, :second)
      assert Posts.delete_expired_posts(later) == 1

      assert Repo.get!(Post, expired.id).deleted_at
      refute Repo.get!(Post, pending.id).deleted_at
      refute Repo.get!(Post, plain.id).deleted_at

      # Already-deleted posts aren't picked up again.
      assert Posts.delete_expired_posts(later) == 0
    end

    test "fixes the parent's reply count like a manual delete" do
      identity = create_user("replytimer", "replytimer@test.com")
      {:ok, parent} = Posts.create_post(identity.id, %{"content" => "parent"})

      {:ok, _reply} =
        Posts.create_post(identity.id, %{
          "content" => "reply",
          "parent_id" => parent.id,
          "expires_in" => 300
        })

      assert Repo.get!(Post, parent.id).reply_count == 1
      assert Posts.delete_expired_posts(DateTime.add(DateTime.utc_now(), 600, :second)) == 1
      assert Repo.get!(Post, parent.id).reply_count == 0
    end
  end
end

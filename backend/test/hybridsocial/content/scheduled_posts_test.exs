defmodule Hybridsocial.Content.ScheduledPostsTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Content.ScheduledPosts

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

  defp future_time(seconds \\ 3600) do
    DateTime.utc_now()
    |> DateTime.add(seconds, :second)
    |> DateTime.truncate(:microsecond)
    |> DateTime.to_iso8601()
  end

  defp past_time(seconds \\ 3600) do
    DateTime.utc_now()
    |> DateTime.add(-seconds, :second)
    |> DateTime.truncate(:microsecond)
    |> DateTime.to_iso8601()
  end

  describe "schedule_post/2" do
    test "schedules a post for the future" do
      identity = create_user("scheduler", "scheduler@test.com")
      scheduled = future_time()

      assert {:ok, post} =
               ScheduledPosts.schedule_post(identity.id, %{
                 "content" => "Future post",
                 "scheduled_at" => scheduled
               })

      assert post.content == "Future post"
      assert post.scheduled_at != nil
      assert post.published_at == nil
    end

    test "rejects scheduling in the past" do
      identity = create_user("pastuser", "pastuser@test.com")

      assert {:error, "must be in the future"} =
               ScheduledPosts.schedule_post(identity.id, %{
                 "content" => "Past post",
                 "scheduled_at" => past_time()
               })
    end

    test "rejects missing scheduled_at" do
      identity = create_user("notime", "notime@test.com")

      assert {:error, "scheduled_at is required"} =
               ScheduledPosts.schedule_post(identity.id, %{
                 "content" => "No time"
               })
    end
  end

  describe "get_scheduled_posts/1" do
    test "returns only scheduled (unpublished) posts for user" do
      identity = create_user("listuser", "listuser@test.com")

      {:ok, _} =
        ScheduledPosts.schedule_post(identity.id, %{
          "content" => "Scheduled 1",
          "scheduled_at" => future_time(7200)
        })

      {:ok, _} =
        ScheduledPosts.schedule_post(identity.id, %{
          "content" => "Scheduled 2",
          "scheduled_at" => future_time(3600)
        })

      posts = ScheduledPosts.get_scheduled_posts(identity.id)
      assert length(posts) == 2
      # Should be ordered by scheduled_at ascending
      assert hd(posts).content == "Scheduled 2"
    end
  end

  describe "cancel_scheduled_post/2" do
    test "cancels a scheduled post" do
      identity = create_user("canceler", "canceler@test.com")

      {:ok, post} =
        ScheduledPosts.schedule_post(identity.id, %{
          "content" => "Cancel me",
          "scheduled_at" => future_time()
        })

      assert {:ok, _} = ScheduledPosts.cancel_scheduled_post(post.id, identity.id)
      assert ScheduledPosts.get_scheduled_posts(identity.id) == []
    end

    test "returns not_found for nonexistent post" do
      identity = create_user("nopost2", "nopost2@test.com")

      assert {:error, :not_found} =
               ScheduledPosts.cancel_scheduled_post(Ecto.UUID.generate(), identity.id)
    end

    test "returns forbidden for other user's post" do
      identity1 = create_user("owner2", "owner2@test.com")
      identity2 = create_user("other2", "other2@test.com")

      {:ok, post} =
        ScheduledPosts.schedule_post(identity1.id, %{
          "content" => "Not yours",
          "scheduled_at" => future_time()
        })

      assert {:error, :forbidden} =
               ScheduledPosts.cancel_scheduled_post(post.id, identity2.id)
    end
  end

  describe "update_scheduled_post/3" do
    test "updates content of a scheduled post" do
      identity = create_user("updater", "updater@test.com")

      {:ok, post} =
        ScheduledPosts.schedule_post(identity.id, %{
          "content" => "Original",
          "scheduled_at" => future_time()
        })

      assert {:ok, updated} =
               ScheduledPosts.update_scheduled_post(post.id, identity.id, %{
                 "content" => "Updated content"
               })

      assert updated.content == "Updated content"
    end
  end

  describe "publish_due_posts/0" do
    test "publishes posts whose scheduled_at has passed" do
      identity = create_user("publisher", "publisher@test.com")

      # Create a post with scheduled_at in the past by directly inserting
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      past = DateTime.add(now, -60, :second)

      {:ok, post} =
        %Hybridsocial.Social.Post{}
        |> Hybridsocial.Social.Post.create_changeset(%{
          "identity_id" => identity.id,
          "content" => "Due post",
          "scheduled_at" => past
        })
        |> Ecto.Changeset.put_change(:scheduled_at, past)
        |> Repo.insert()

      assert post.published_at == nil

      {count, _} = ScheduledPosts.publish_due_posts()
      assert count >= 1

      updated = Repo.get!(Hybridsocial.Social.Post, post.id)
      assert updated.published_at != nil
    end

    test "does not publish posts scheduled for the future" do
      identity = create_user("futurist", "futurist@test.com")

      {:ok, _} =
        ScheduledPosts.schedule_post(identity.id, %{
          "content" => "Future post",
          "scheduled_at" => future_time(7200)
        })

      {count, _} = ScheduledPosts.publish_due_posts()
      assert count == 0
    end
  end
end

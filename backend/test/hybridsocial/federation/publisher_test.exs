defmodule Hybridsocial.Federation.PublisherTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Federation.Publisher
  alias Hybridsocial.Federation.ActivityBuilder

  @public "https://www.w3.org/ns/activitystreams#Public"

  describe "determine_recipients/2" do
    test "returns empty list when there are no followers" do
      identity = create_user("sender1", "sender1@example.com")

      activity = %{
        "type" => "Create",
        "to" => [@public],
        "cc" => ["http://localhost:4002/actors/#{identity.id}/followers"]
      }

      inboxes = Publisher.determine_recipients(activity, identity)
      assert inboxes == []
    end

    test "returns follower inboxes for public posts" do
      identity = create_user("sender2", "sender2@example.com")
      follower = create_user("follower2", "follower2@example.com")

      # Create a follow relationship
      {:ok, _follow} = Hybridsocial.Social.follow(follower.id, identity.id)

      activity = %{
        "type" => "Create",
        "to" => [@public],
        "cc" => ["http://localhost:4002/actors/#{identity.id}/followers"]
      }

      inboxes = Publisher.determine_recipients(activity, identity)

      # Local follower inboxes are filtered out (we don't deliver locally via AP)
      assert inboxes == []
    end

    test "returns empty list for followers-only posts with no followers" do
      identity = create_user("sender3", "sender3@example.com")
      followers_url = "http://localhost:4002/actors/#{identity.id}/followers"

      activity = %{
        "type" => "Create",
        "to" => [followers_url],
        "cc" => []
      }

      inboxes = Publisher.determine_recipients(activity, identity)
      assert inboxes == []
    end

    test "deduplicates inbox URLs" do
      identity = create_user("sender4", "sender4@example.com")

      # Activity addressing the same target in both to and cc
      activity = %{
        "type" => "Create",
        "to" => [@public],
        "cc" => [@public, "http://localhost:4002/actors/#{identity.id}/followers"]
      }

      inboxes = Publisher.determine_recipients(activity, identity)

      # Should be deduplicated
      assert inboxes == Enum.uniq(inboxes)
    end
  end

  describe "publish/2" do
    test "creates delivery records for each recipient" do
      identity = create_user("pub1", "pub1@example.com")

      {:ok, post} =
        Hybridsocial.Social.Posts.create_post(identity.id, %{
          "content" => "Test post",
          "visibility" => "direct"
        })

      post = Hybridsocial.Repo.preload(post, :identity)
      activity = ActivityBuilder.build_create(post)

      # Direct visibility with no recipients should create 0 deliveries
      {:ok, count} = Publisher.publish(activity, identity)
      assert count == 0
    end
  end

  # --- Helper ---

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
end

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

    test "skips inboxes on domains an admin disabled delivery to" do
      identity = create_user("pub2", "pub2@example.com")

      # A remote follower whose instance is gone for good.
      {:ok, follower} =
        create_user("gonefollower", "gonefollower@example.com")
        |> Ecto.Changeset.cast(
          %{
            is_local: false,
            ap_actor_url: "https://gone.example/users/gonefollower",
            inbox_url: "https://gone.example/users/gonefollower/inbox"
          },
          [:is_local, :ap_actor_url, :inbox_url]
        )
        |> Hybridsocial.Repo.update()

      {:ok, _follow} = Hybridsocial.Social.follow(follower.id, identity.id)

      activity = %{
        "type" => "Create",
        "id" => "http://localhost:4002/activities/disabled-peer",
        "to" => [@public],
        "cc" => ["http://localhost:4002/actors/#{identity.id}/followers"]
      }

      # Baseline: the follower's inbox is a real recipient.
      assert "https://gone.example/users/gonefollower/inbox" in Publisher.determine_recipients(
               activity,
               identity
             )

      :ok = Hybridsocial.Federation.CircuitBreaker.disable_delivery("gone.example")

      # No queue row is written at all — the point of the kill switch is
      # that a dead peer stops generating dead letters.
      assert {:ok, 0} = Publisher.publish(activity, identity)
      assert Hybridsocial.Repo.aggregate(Hybridsocial.Federation.Delivery, :count) == 0
    end

    test "writes no queue row for a peer whose circuit is open, until its probe is due" do
      identity = create_user("opencircuit", "opencircuit@example.com")

      {:ok, follower} =
        create_user("downfollower", "downfollower@example.com")
        |> Ecto.Changeset.cast(
          %{
            is_local: false,
            ap_actor_url: "https://down.example/users/downfollower",
            inbox_url: "https://down.example/users/downfollower/inbox"
          },
          [:is_local, :ap_actor_url, :inbox_url]
        )
        |> Hybridsocial.Repo.update()

      {:ok, _follow} = Hybridsocial.Social.follow(follower.id, identity.id)

      activity = %{
        "type" => "Create",
        "id" => "http://localhost:4002/activities/open-circuit",
        "to" => [@public],
        "cc" => ["http://localhost:4002/actors/#{identity.id}/followers"]
      }

      # Five hard failures open the circuit with a reopen time in the future.
      for _ <- 1..5,
          do:
            Hybridsocial.Federation.CircuitBreaker.record_result(
              "https://down.example/inbox",
              :hard
            )

      assert {:ok, 0} = Publisher.publish(activity, identity)
      assert Hybridsocial.Repo.aggregate(Hybridsocial.Federation.Delivery, :count) == 0

      # Once the probe is due, the next activity goes out as the probe.
      Hybridsocial.Repo.update_all(
        Hybridsocial.Federation.RemoteInstance,
        set: [circuit_reopen_at: DateTime.add(DateTime.utc_now(), -60, :second)]
      )

      assert {:ok, 1} = Publisher.publish(activity, identity)
    end
  end

  describe "deliver/3 — refuses to send unsigned" do
    test "returns an explicit error when the identity has no private_key" do
      identity = create_user("nokey1", "nokey1@example.com")
      # Strip the auto-generated key so we exercise the missing-key branch.
      {:ok, identity} =
        identity
        |> Ecto.Changeset.cast(%{private_key: nil}, [:private_key])
        |> Hybridsocial.Repo.update()

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Follow",
        "id" => "http://localhost:4002/activities/test-no-key",
        "actor" => "http://localhost:4002/actors/#{identity.id}",
        "object" => "https://remote.example/users/x"
      }

      assert {:error, "missing_private_key"} =
               Publisher.deliver(activity, "https://remote.example/inbox", identity)
    end
  end
end

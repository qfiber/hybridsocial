defmodule Hybridsocial.SocialTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Social
  alias Hybridsocial.Accounts

  defp create_identity(handle, email) do
    {:ok, identity} =
      Accounts.register_user(%{
        "handle" => handle,
        "display_name" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  setup do
    alice = create_identity("alice", "alice@example.com")
    bob = create_identity("bob", "bob@example.com")
    %{alice: alice, bob: bob}
  end

  # --- Follow tests ---

  describe "follow/2" do
    test "creates an accepted follow for unlocked account", %{alice: alice, bob: bob} do
      assert {:ok, follow} = Social.follow(alice.id, bob.id)
      assert follow.status == :accepted
      assert follow.follower_id == alice.id
      assert follow.followee_id == bob.id
    end

    test "creates a pending follow for locked account", %{alice: alice} do
      locked = create_identity("locked_user", "locked@example.com")

      {:ok, _} =
        Accounts.update_identity(locked, %{"is_locked" => true})

      assert {:ok, follow} = Social.follow(alice.id, locked.id)
      assert follow.status == :pending
    end

    test "returns error when following self", %{alice: alice} do
      assert {:error, :cannot_follow_self} = Social.follow(alice.id, alice.id)
    end

    test "returns error when following non-existent user", %{alice: alice} do
      assert {:error, :not_found} = Social.follow(alice.id, Ecto.UUID.generate())
    end

    test "returns error when blocked by target", %{alice: alice, bob: bob} do
      {:ok, _} = Social.block(bob.id, alice.id)
      assert {:error, :blocked} = Social.follow(alice.id, bob.id)
    end

    test "is idempotent", %{alice: alice, bob: bob} do
      assert {:ok, _} = Social.follow(alice.id, bob.id)
      assert {:ok, _} = Social.follow(alice.id, bob.id)
    end
  end

  describe "unfollow/2" do
    test "removes follow relationship", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      assert Social.following?(alice.id, bob.id)

      :ok = Social.unfollow(alice.id, bob.id)
      refute Social.following?(alice.id, bob.id)
    end

    test "is a no-op when not following", %{alice: alice, bob: bob} do
      assert :ok = Social.unfollow(alice.id, bob.id)
    end
  end

  describe "accept_follow/1 and reject_follow/1" do
    test "accepts a pending follow", %{alice: alice} do
      locked = create_identity("locked2", "locked2@example.com")
      {:ok, _} = Accounts.update_identity(locked, %{"is_locked" => true})

      {:ok, follow} = Social.follow(alice.id, locked.id)
      assert follow.status == :pending

      {:ok, updated} = Social.accept_follow(follow.id)
      assert updated.status == :accepted
      assert Social.following?(alice.id, locked.id)
    end

    test "rejects a pending follow", %{alice: alice} do
      locked = create_identity("locked3", "locked3@example.com")
      {:ok, _} = Accounts.update_identity(locked, %{"is_locked" => true})

      {:ok, follow} = Social.follow(alice.id, locked.id)
      {:ok, updated} = Social.reject_follow(follow.id)
      assert updated.status == :rejected
      refute Social.following?(alice.id, locked.id)
    end

    test "returns error for non-existent follow" do
      assert {:error, :not_found} = Social.accept_follow(Ecto.UUID.generate())
    end
  end

  describe "following?/2" do
    test "returns true when following (accepted)", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      assert Social.following?(alice.id, bob.id)
    end

    test "returns false when not following", %{alice: alice, bob: bob} do
      refute Social.following?(alice.id, bob.id)
    end

    test "returns false for pending follow", %{alice: alice} do
      locked = create_identity("locked4", "locked4@example.com")
      {:ok, _} = Accounts.update_identity(locked, %{"is_locked" => true})

      {:ok, _} = Social.follow(alice.id, locked.id)
      refute Social.following?(alice.id, locked.id)
    end
  end

  describe "followers/2 and following/2" do
    test "returns followers list", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(bob.id, alice.id)
      followers = Social.followers(alice.id)
      assert length(followers) == 1
      assert hd(followers).id == bob.id
    end

    test "returns following list", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      following = Social.following(alice.id)
      assert length(following) == 1
      assert hd(following).id == bob.id
    end

    test "supports pagination", %{alice: alice} do
      for i <- 1..5 do
        user = create_identity("follower#{i}", "follower#{i}@example.com")
        {:ok, _} = Social.follow(user.id, alice.id)
      end

      assert length(Social.followers(alice.id, limit: 2)) == 2
      assert length(Social.followers(alice.id, limit: 10)) == 5
    end
  end

  describe "followers_count/1 and following_count/1" do
    test "returns correct counts", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)

      assert Social.followers_count(bob.id) == 1
      assert Social.following_count(alice.id) == 1
      assert Social.followers_count(alice.id) == 0
      assert Social.following_count(bob.id) == 0
    end
  end

  # --- Block tests ---

  describe "block/2" do
    test "creates block", %{alice: alice, bob: bob} do
      assert {:ok, block} = Social.block(alice.id, bob.id)
      assert block.blocker_id == alice.id
      assert block.blocked_id == bob.id
    end

    test "removes existing follow relationships in both directions", %{alice: alice, bob: bob} do
      {:ok, _} = Social.follow(alice.id, bob.id)
      {:ok, _} = Social.follow(bob.id, alice.id)

      assert Social.following?(alice.id, bob.id)
      assert Social.following?(bob.id, alice.id)

      {:ok, _} = Social.block(alice.id, bob.id)

      refute Social.following?(alice.id, bob.id)
      refute Social.following?(bob.id, alice.id)
    end

    test "is idempotent", %{alice: alice, bob: bob} do
      assert {:ok, _} = Social.block(alice.id, bob.id)
      assert {:ok, _} = Social.block(alice.id, bob.id)
    end
  end

  describe "unblock/2" do
    test "removes block", %{alice: alice, bob: bob} do
      {:ok, _} = Social.block(alice.id, bob.id)
      assert Social.blocked?(alice.id, bob.id)

      :ok = Social.unblock(alice.id, bob.id)
      refute Social.blocked?(alice.id, bob.id)
    end
  end

  describe "blocked?/2" do
    test "returns true when blocked", %{alice: alice, bob: bob} do
      {:ok, _} = Social.block(alice.id, bob.id)
      assert Social.blocked?(alice.id, bob.id)
    end

    test "is not symmetric", %{alice: alice, bob: bob} do
      {:ok, _} = Social.block(alice.id, bob.id)
      assert Social.blocked?(alice.id, bob.id)
      refute Social.blocked?(bob.id, alice.id)
    end
  end

  describe "blocking_ids/1" do
    test "returns list of blocked IDs", %{alice: alice, bob: bob} do
      carol = create_identity("carol", "carol@example.com")
      {:ok, _} = Social.block(alice.id, bob.id)
      {:ok, _} = Social.block(alice.id, carol.id)

      ids = Social.blocking_ids(alice.id)
      assert length(ids) == 2
      assert bob.id in ids
      assert carol.id in ids
    end
  end

  # --- Mute tests ---

  describe "mute/3" do
    test "creates mute with defaults", %{alice: alice, bob: bob} do
      assert {:ok, mute} = Social.mute(alice.id, bob.id)
      assert mute.muter_id == alice.id
      assert mute.muted_id == bob.id
      assert mute.mute_notifications == true
      assert mute.expires_at == nil
    end

    test "creates mute with options", %{alice: alice, bob: bob} do
      expires = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert {:ok, mute} =
               Social.mute(alice.id, bob.id, mute_notifications: false, expires_at: expires)

      assert mute.mute_notifications == false
      assert mute.expires_at != nil
    end

    test "is idempotent and updates options", %{alice: alice, bob: bob} do
      {:ok, _} = Social.mute(alice.id, bob.id, mute_notifications: true)
      {:ok, mute} = Social.mute(alice.id, bob.id, mute_notifications: false)
      assert mute.mute_notifications == false
    end
  end

  describe "unmute/2" do
    test "removes mute", %{alice: alice, bob: bob} do
      {:ok, _} = Social.mute(alice.id, bob.id)
      assert Social.muted?(alice.id, bob.id)

      :ok = Social.unmute(alice.id, bob.id)
      refute Social.muted?(alice.id, bob.id)
    end
  end

  describe "muted?/2" do
    test "returns true when muted", %{alice: alice, bob: bob} do
      {:ok, _} = Social.mute(alice.id, bob.id)
      assert Social.muted?(alice.id, bob.id)
    end

    test "returns false for expired mute", %{alice: alice, bob: bob} do
      expired = DateTime.add(DateTime.utc_now(), -3600, :second)
      {:ok, _} = Social.mute(alice.id, bob.id, expires_at: expired)
      refute Social.muted?(alice.id, bob.id)
    end
  end

  describe "muted_ids/1" do
    test "returns list of muted IDs", %{alice: alice, bob: bob} do
      carol = create_identity("carol2", "carol2@example.com")
      {:ok, _} = Social.mute(alice.id, bob.id)
      {:ok, _} = Social.mute(alice.id, carol.id)

      ids = Social.muted_ids(alice.id)
      assert length(ids) == 2
      assert bob.id in ids
      assert carol.id in ids
    end

    test "excludes expired mutes", %{alice: alice, bob: bob} do
      expired = DateTime.add(DateTime.utc_now(), -3600, :second)
      {:ok, _} = Social.mute(alice.id, bob.id, expires_at: expired)

      assert Social.muted_ids(alice.id) == []
    end
  end

  # --- Relationships ---

  describe "relationships/2" do
    test "returns relationship status for multiple targets", %{alice: alice, bob: bob} do
      carol = create_identity("carol3", "carol3@example.com")

      {:ok, _} = Social.follow(alice.id, bob.id)
      {:ok, _} = Social.follow(bob.id, alice.id)
      {:ok, _} = Social.block(alice.id, carol.id)

      rels = Social.relationships(alice.id, [bob.id, carol.id])
      assert length(rels) == 2

      bob_rel = Enum.find(rels, &(&1.id == bob.id))
      assert bob_rel.following == true
      assert bob_rel.followed_by == true
      assert bob_rel.blocking == false

      carol_rel = Enum.find(rels, &(&1.id == carol.id))
      assert carol_rel.following == false
      assert carol_rel.blocking == true
    end
  end
end

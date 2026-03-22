defmodule Hybridsocial.NotificationsTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Notifications

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

  # ---------------------------------------------------------------------------
  # create_notification/1
  # ---------------------------------------------------------------------------

  describe "create_notification/1" do
    test "creates a notification with valid attrs" do
      alice = create_user("notif_alice1", "notif_alice1@example.com")
      bob = create_user("notif_bob1", "notif_bob1@example.com")

      assert {:ok, notification} =
               Notifications.create_notification(%{
                 recipient_id: alice.id,
                 actor_id: bob.id,
                 type: "follow"
               })

      assert notification.recipient_id == alice.id
      assert notification.actor_id == bob.id
      assert notification.type == "follow"
      assert notification.read == false
    end

    test "skips notification when actor == recipient" do
      alice = create_user("notif_alice2", "notif_alice2@example.com")

      assert {:ok, :skipped} =
               Notifications.create_notification(%{
                 recipient_id: alice.id,
                 actor_id: alice.id,
                 type: "follow"
               })
    end

    test "skips notification when recipient has muted the actor" do
      alice = create_user("notif_alice3", "notif_alice3@example.com")
      bob = create_user("notif_bob3", "notif_bob3@example.com")

      {:ok, _mute} = Hybridsocial.Social.mute(alice.id, bob.id)

      assert {:ok, :skipped} =
               Notifications.create_notification(%{
                 recipient_id: alice.id,
                 actor_id: bob.id,
                 type: "follow"
               })
    end

    test "creates notification with target_type and target_id" do
      alice = create_user("notif_alice4", "notif_alice4@example.com")
      bob = create_user("notif_bob4", "notif_bob4@example.com")
      post_id = Ecto.UUID.generate()

      assert {:ok, notification} =
               Notifications.create_notification(%{
                 recipient_id: alice.id,
                 actor_id: bob.id,
                 type: "reaction",
                 target_type: "post",
                 target_id: post_id
               })

      assert notification.target_type == "post"
      assert notification.target_id == post_id
    end
  end

  # ---------------------------------------------------------------------------
  # list_notifications/2
  # ---------------------------------------------------------------------------

  describe "list_notifications/2" do
    test "returns notifications for the given identity" do
      alice = create_user("notif_alice5", "notif_alice5@example.com")
      bob = create_user("notif_bob5", "notif_bob5@example.com")

      {:ok, _} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      notifications = Notifications.list_notifications(alice.id)
      assert length(notifications) == 1
      assert hd(notifications).type == "follow"
    end

    test "filters by types" do
      alice = create_user("notif_alice6", "notif_alice6@example.com")
      bob = create_user("notif_bob6", "notif_bob6@example.com")

      {:ok, _} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      {:ok, _} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "reaction",
          target_type: "post",
          target_id: Ecto.UUID.generate()
        })

      notifications = Notifications.list_notifications(alice.id, types: ["follow"])
      assert length(notifications) == 1
      assert hd(notifications).type == "follow"
    end

    test "filters by exclude_types" do
      alice = create_user("notif_alice7", "notif_alice7@example.com")
      bob = create_user("notif_bob7", "notif_bob7@example.com")

      {:ok, _} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      {:ok, _} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "reaction",
          target_type: "post",
          target_id: Ecto.UUID.generate()
        })

      notifications = Notifications.list_notifications(alice.id, exclude_types: ["follow"])
      assert length(notifications) == 1
      assert hd(notifications).type == "reaction"
    end

    test "respects limit" do
      alice = create_user("notif_alice8", "notif_alice8@example.com")
      bob = create_user("notif_bob8", "notif_bob8@example.com")

      for _ <- 1..5 do
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })
      end

      notifications = Notifications.list_notifications(alice.id, limit: 3)
      assert length(notifications) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # get_notification/2
  # ---------------------------------------------------------------------------

  describe "get_notification/2" do
    test "returns the notification if owned by identity" do
      alice = create_user("notif_alice9", "notif_alice9@example.com")
      bob = create_user("notif_bob9", "notif_bob9@example.com")

      {:ok, created} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      notification = Notifications.get_notification(created.id, alice.id)
      assert notification.id == created.id
    end

    test "returns nil if not owned by identity" do
      alice = create_user("notif_alice10", "notif_alice10@example.com")
      bob = create_user("notif_bob10", "notif_bob10@example.com")

      {:ok, created} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      assert is_nil(Notifications.get_notification(created.id, bob.id))
    end
  end

  # ---------------------------------------------------------------------------
  # mark_read/2, mark_all_read/1
  # ---------------------------------------------------------------------------

  describe "mark_read/2" do
    test "marks a notification as read" do
      alice = create_user("notif_alice11", "notif_alice11@example.com")
      bob = create_user("notif_bob11", "notif_bob11@example.com")

      {:ok, created} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      assert {:ok, updated} = Notifications.mark_read(created.id, alice.id)
      assert updated.read == true
    end

    test "returns error if notification not found" do
      alice = create_user("notif_alice12", "notif_alice12@example.com")
      assert {:error, :not_found} = Notifications.mark_read(Ecto.UUID.generate(), alice.id)
    end
  end

  describe "mark_all_read/1" do
    test "marks all notifications as read for the identity" do
      alice = create_user("notif_alice13", "notif_alice13@example.com")
      bob = create_user("notif_bob13", "notif_bob13@example.com")

      for _ <- 1..3 do
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })
      end

      assert Notifications.unread_count(alice.id) == 3
      :ok = Notifications.mark_all_read(alice.id)
      assert Notifications.unread_count(alice.id) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # unread_count/1
  # ---------------------------------------------------------------------------

  describe "unread_count/1" do
    test "counts unread notifications" do
      alice = create_user("notif_alice14", "notif_alice14@example.com")
      bob = create_user("notif_bob14", "notif_bob14@example.com")

      {:ok, n1} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      {:ok, _} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "reaction",
          target_type: "post",
          target_id: Ecto.UUID.generate()
        })

      assert Notifications.unread_count(alice.id) == 2

      Notifications.mark_read(n1.id, alice.id)
      assert Notifications.unread_count(alice.id) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # dismiss_notification/2
  # ---------------------------------------------------------------------------

  describe "dismiss_notification/2" do
    test "deletes the notification" do
      alice = create_user("notif_alice15", "notif_alice15@example.com")
      bob = create_user("notif_bob15", "notif_bob15@example.com")

      {:ok, created} =
        Notifications.create_notification(%{
          recipient_id: alice.id,
          actor_id: bob.id,
          type: "follow"
        })

      assert {:ok, _} = Notifications.dismiss_notification(created.id, alice.id)
      assert is_nil(Notifications.get_notification(created.id, alice.id))
    end

    test "returns error if not found" do
      alice = create_user("notif_alice16", "notif_alice16@example.com")

      assert {:error, :not_found} =
               Notifications.dismiss_notification(Ecto.UUID.generate(), alice.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Preferences
  # ---------------------------------------------------------------------------

  describe "get_preferences/1" do
    test "returns empty map when no preferences set" do
      alice = create_user("notif_alice17", "notif_alice17@example.com")
      assert Notifications.get_preferences(alice.id) == %{}
    end

    test "returns preferences as map" do
      alice = create_user("notif_alice18", "notif_alice18@example.com")

      {:ok, _} =
        Notifications.update_preference(alice.id, "follow", %{"email" => true, "push" => false})

      prefs = Notifications.get_preferences(alice.id)
      assert prefs["follow"].email == true
      assert prefs["follow"].push == false
      assert prefs["follow"].in_app == true
    end
  end

  describe "update_preference/3" do
    test "creates a preference if it does not exist" do
      alice = create_user("notif_alice19", "notif_alice19@example.com")

      assert {:ok, pref} = Notifications.update_preference(alice.id, "follow", %{"email" => true})
      assert pref.type == "follow"
      assert pref.email == true
    end

    test "updates an existing preference" do
      alice = create_user("notif_alice20", "notif_alice20@example.com")

      {:ok, _} = Notifications.update_preference(alice.id, "follow", %{"email" => true})
      {:ok, pref} = Notifications.update_preference(alice.id, "follow", %{"email" => false})
      assert pref.email == false
    end
  end

  describe "should_notify?/3" do
    test "returns default values when no preference set" do
      alice = create_user("notif_alice21", "notif_alice21@example.com")

      assert Notifications.should_notify?(alice.id, "follow", :push) == true
      assert Notifications.should_notify?(alice.id, "follow", :in_app) == true
      assert Notifications.should_notify?(alice.id, "follow", :email) == false
    end

    test "returns preference values when set" do
      alice = create_user("notif_alice22", "notif_alice22@example.com")

      {:ok, _} =
        Notifications.update_preference(alice.id, "follow", %{"email" => true, "push" => false})

      assert Notifications.should_notify?(alice.id, "follow", :email) == true
      assert Notifications.should_notify?(alice.id, "follow", :push) == false
      assert Notifications.should_notify?(alice.id, "follow", :in_app) == true
    end
  end

  # ---------------------------------------------------------------------------
  # Convenience functions
  # ---------------------------------------------------------------------------

  describe "notify_follow/2" do
    test "creates a follow notification" do
      alice = create_user("notif_alice23", "notif_alice23@example.com")
      bob = create_user("notif_bob23", "notif_bob23@example.com")

      assert {:ok, notification} = Notifications.notify_follow(bob.id, alice.id)
      assert notification.type == "follow"
      assert notification.recipient_id == alice.id
      assert notification.actor_id == bob.id
    end
  end
end

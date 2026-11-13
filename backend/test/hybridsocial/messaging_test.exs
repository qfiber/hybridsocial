defmodule Hybridsocial.MessagingTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Messaging

  # ---------------------------------------------------------------------------
  # Direct Conversations
  # ---------------------------------------------------------------------------

  describe "find_or_create_direct/2" do
    test "creates a new direct conversation" do
      alice = create_trusted_user("msg_alice", "msg_alice@example.com")
      bob = create_trusted_user("msg_bob", "msg_bob@example.com")

      assert {:ok, conversation} = Messaging.find_or_create_direct(alice.id, bob.id)
      assert conversation.type == "direct"
    end

    test "returns existing direct conversation" do
      alice = create_trusted_user("msg_alice2", "msg_alice2@example.com")
      bob = create_trusted_user("msg_bob2", "msg_bob2@example.com")

      {:ok, conv1} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, conv2} = Messaging.find_or_create_direct(alice.id, bob.id)

      assert conv1.id == conv2.id
    end

    test "returns existing conversation regardless of direction" do
      alice = create_trusted_user("msg_alice3", "msg_alice3@example.com")
      bob = create_trusted_user("msg_bob3", "msg_bob3@example.com")

      {:ok, conv1} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, conv2} = Messaging.find_or_create_direct(bob.id, alice.id)

      assert conv1.id == conv2.id
    end

    test "cannot message self" do
      alice = create_trusted_user("msg_alice4", "msg_alice4@example.com")
      assert {:error, :cannot_message_self} = Messaging.find_or_create_direct(alice.id, alice.id)
    end

    test "respects DM preferences - nobody" do
      alice = create_trusted_user("msg_alice5", "msg_alice5@example.com")
      bob = create_trusted_user("msg_bob5", "msg_bob5@example.com")

      {:ok, _} = Messaging.update_dm_preferences(bob.id, %{"allow_dms_from" => "nobody"})

      assert {:error, :dm_not_allowed} = Messaging.find_or_create_direct(alice.id, bob.id)
    end

    test "respects block" do
      alice = create_trusted_user("msg_alice6", "msg_alice6@example.com")
      bob = create_trusted_user("msg_bob6", "msg_bob6@example.com")

      {:ok, _} = Hybridsocial.Social.block(bob.id, alice.id)

      assert {:error, :dm_not_allowed} = Messaging.find_or_create_direct(alice.id, bob.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Group DMs
  # ---------------------------------------------------------------------------

  describe "create_group_dm/2" do
    test "creates a group DM" do
      alice = create_trusted_user("grp_alice", "grp_alice@example.com")
      bob = create_trusted_user("grp_bob", "grp_bob@example.com")
      carol = create_trusted_user("grp_carol", "grp_carol@example.com")
      opt_into_group_dms(bob)
      opt_into_group_dms(carol)

      assert {:ok, conversation} = Messaging.create_group_dm(alice.id, [bob.id, carol.id])
      assert conversation.type == "group_dm"
    end

    test "refuses participants who haven't opted into group DMs, naming them" do
      alice = create_trusted_user("grp_optout_a")
      bob = create_trusted_user("grp_optout_b")
      carol = create_trusted_user("grp_optout_c")
      opt_into_group_dms(bob)

      assert {:error, :group_dm_not_allowed, [refused]} =
               Messaging.create_group_dm(alice.id, [bob.id, carol.id])

      assert refused == carol.id
    end

    test "refuses a participant who blocked the creator, or whom the creator blocked" do
      alice = create_trusted_user("grp_blk_a")
      bob = create_trusted_user("grp_blk_b")
      carol = create_trusted_user("grp_blk_c")
      opt_into_group_dms(bob)
      opt_into_group_dms(carol)

      {:ok, _} = Hybridsocial.Social.block(bob.id, alice.id)

      assert {:error, :group_dm_not_allowed, [refused]} =
               Messaging.create_group_dm(alice.id, [bob.id, carol.id])

      assert refused == bob.id

      {:ok, _} = Hybridsocial.Social.block(alice.id, carol.id)

      assert {:error, :group_dm_not_allowed, refused} =
               Messaging.create_group_dm(alice.id, [bob.id, carol.id])

      assert Enum.sort(refused) == Enum.sort([bob.id, carol.id])
    end

    test "honours allow_dms_from" do
      alice = create_trusted_user("grp_from_a")
      bob = create_trusted_user("grp_from_b")
      carol = create_trusted_user("grp_from_c")
      opt_into_group_dms(bob, %{"allow_dms_from" => "nobody"})
      opt_into_group_dms(carol, %{"allow_dms_from" => "followers"})

      assert {:error, :group_dm_not_allowed, refused} =
               Messaging.create_group_dm(alice.id, [bob.id, carol.id])

      assert Enum.sort(refused) == Enum.sort([bob.id, carol.id])

      # Carol follows Alice, so "followers" lets Alice in; Bob still says nobody.
      {:ok, _} = Hybridsocial.Social.follow(carol.id, alice.id)

      assert {:error, :group_dm_not_allowed, [refused]} =
               Messaging.create_group_dm(alice.id, [bob.id, carol.id])

      assert refused == bob.id
    end

    test "refuses remote participants" do
      alice = create_trusted_user("grp_rem_a")
      bob = create_trusted_user("grp_rem_b")
      opt_into_group_dms(bob)

      remote =
        create_trusted_user("grp_rem_c")
        |> Ecto.Changeset.change(is_local: false)
        |> Hybridsocial.Repo.update!()

      opt_into_group_dms(remote)

      assert {:error, :group_dm_remote_not_supported, [remote_id]} =
               Messaging.create_group_dm(alice.id, [bob.id, remote.id])

      assert remote_id == remote.id
    end

    test "refuses unknown participant ids" do
      alice = create_trusted_user("grp_unk_a")
      bob = create_trusted_user("grp_unk_b")
      opt_into_group_dms(bob)

      for bad <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert {:error, :recipient_not_found} = Messaging.create_group_dm(alice.id, [bob.id, bad])
      end
    end

    test "caps the participant count" do
      alice = create_trusted_user("grp_cap_a")
      max = Messaging.group_dm_max_participants()
      ids = for _ <- 1..max, do: Ecto.UUID.generate()

      assert {:error, :group_dm_too_large, ^max} = Messaging.create_group_dm(alice.id, ids)
    end

    test "requires at least 2 participants" do
      alice = create_trusted_user("grp_alice2", "grp_alice2@example.com")
      assert {:error, :insufficient_participants} = Messaging.create_group_dm(alice.id, [])
    end
  end

  # ---------------------------------------------------------------------------
  # Conversation Operations
  # ---------------------------------------------------------------------------

  describe "get_conversation/2" do
    test "returns conversation for participant" do
      alice = create_trusted_user("gc_alice", "gc_alice@example.com")
      bob = create_trusted_user("gc_bob", "gc_bob@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      assert {:ok, fetched} = Messaging.get_conversation(conv.id, alice.id)
      assert fetched.id == conv.id
    end

    test "returns error for non-participant" do
      alice = create_trusted_user("gc_alice2", "gc_alice2@example.com")
      bob = create_trusted_user("gc_bob2", "gc_bob2@example.com")
      carol = create_trusted_user("gc_carol", "gc_carol@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      assert {:error, :not_found} = Messaging.get_conversation(conv.id, carol.id)
    end
  end

  describe "list_conversations/2" do
    test "lists conversations for user" do
      alice = create_trusted_user("lc_alice", "lc_alice@example.com")
      bob = create_trusted_user("lc_bob", "lc_bob@example.com")

      {:ok, _} = Messaging.find_or_create_direct(alice.id, bob.id)

      conversations = Messaging.list_conversations(alice.id)
      assert length(conversations) == 1
    end

    test "returns empty list when no conversations" do
      alice = create_trusted_user("lc_alice2", "lc_alice2@example.com")
      assert Messaging.list_conversations(alice.id) == []
    end
  end

  describe "leave_conversation/2" do
    test "can leave group DM" do
      alice = create_trusted_user("lv_alice", "lv_alice@example.com")
      bob = create_trusted_user("lv_bob", "lv_bob@example.com")
      carol = create_trusted_user("lv_carol", "lv_carol@example.com")
      opt_into_group_dms(bob)
      opt_into_group_dms(carol)

      {:ok, conv} = Messaging.create_group_dm(alice.id, [bob.id, carol.id])
      assert {:ok, _} = Messaging.leave_conversation(conv.id, bob.id)
    end

    test "cannot leave direct conversation" do
      alice = create_trusted_user("lv_alice2", "lv_alice2@example.com")
      bob = create_trusted_user("lv_bob2", "lv_bob2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      assert {:error, :cannot_leave_direct} = Messaging.leave_conversation(conv.id, bob.id)
    end
  end

  describe "mute/unmute conversation" do
    test "mute and unmute a conversation" do
      alice = create_trusted_user("mu_alice", "mu_alice@example.com")
      bob = create_trusted_user("mu_bob", "mu_bob@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)

      {:ok, participant} = Messaging.mute_conversation(conv.id, alice.id)
      assert participant.notifications_enabled == false

      {:ok, participant} = Messaging.unmute_conversation(conv.id, alice.id)
      assert participant.notifications_enabled == true
    end
  end

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------

  describe "send_message/3" do
    test "sends a message in a conversation" do
      alice = create_trusted_user("sm_alice", "sm_alice@example.com")
      bob = create_trusted_user("sm_bob", "sm_bob@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)

      assert {:ok, message} =
               Messaging.send_message(conv.id, alice.id, %{"content" => "Hello Bob!"})

      assert message.content == "Hello Bob!"
      assert message.sender_id == alice.id
      assert message.conversation_id == conv.id
    end

    test "non-participant cannot send message" do
      alice = create_trusted_user("sm_alice2", "sm_alice2@example.com")
      bob = create_trusted_user("sm_bob2", "sm_bob2@example.com")
      carol = create_trusted_user("sm_carol", "sm_carol@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)

      assert {:error, :not_found} =
               Messaging.send_message(conv.id, carol.id, %{"content" => "Hi!"})
    end

    test "creates delivery statuses for recipients" do
      alice = create_trusted_user("sm_alice3", "sm_alice3@example.com")
      bob = create_trusted_user("sm_bob3", "sm_bob3@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, message} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      statuses =
        Hybridsocial.Messaging.DeliveryStatus
        |> where([d], d.message_id == ^message.id)
        |> Repo.all()

      assert length(statuses) == 1
      assert hd(statuses).recipient_id == bob.id
      assert hd(statuses).status == "sent"
    end
  end

  describe "edit_message/3" do
    test "edits a message by its sender" do
      alice = create_trusted_user("em_alice", "em_alice@example.com")
      bob = create_trusted_user("em_bob", "em_bob@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, message} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      assert {:ok, edited} = Messaging.edit_message(message.id, alice.id, "Hello updated!")
      assert edited.content == "Hello updated!"
      assert edited.edited_at != nil
    end

    test "cannot edit another user's message" do
      alice = create_trusted_user("em_alice2", "em_alice2@example.com")
      bob = create_trusted_user("em_bob2", "em_bob2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, message} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      assert {:error, :forbidden} = Messaging.edit_message(message.id, bob.id, "Hacked!")
    end
  end

  describe "delete_message/2" do
    test "soft-deletes a message by its sender" do
      alice = create_trusted_user("dm_alice", "dm_alice@example.com")
      bob = create_trusted_user("dm_bob", "dm_bob@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, message} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      assert {:ok, deleted} = Messaging.delete_message(message.id, alice.id)
      assert deleted.deleted_at != nil
    end

    test "cannot delete another user's message" do
      alice = create_trusted_user("dm_alice2", "dm_alice2@example.com")
      bob = create_trusted_user("dm_bob2", "dm_bob2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, message} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      assert {:error, :forbidden} = Messaging.delete_message(message.id, bob.id)
    end
  end

  describe "get_messages/3" do
    test "returns messages for participant" do
      alice = create_trusted_user("gm_alice", "gm_alice@example.com")
      bob = create_trusted_user("gm_bob", "gm_bob@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, _} = Messaging.send_message(conv.id, alice.id, %{"content" => "Message 1"})
      {:ok, _} = Messaging.send_message(conv.id, bob.id, %{"content" => "Message 2"})

      assert {:ok, messages} = Messaging.get_messages(conv.id, alice.id)
      assert length(messages) == 2
    end

    test "non-participant cannot get messages" do
      alice = create_trusted_user("gm_alice2", "gm_alice2@example.com")
      bob = create_trusted_user("gm_bob2", "gm_bob2@example.com")
      carol = create_trusted_user("gm_carol", "gm_carol@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      assert {:error, :not_found} = Messaging.get_messages(conv.id, carol.id)
    end

    test "does not return soft-deleted messages" do
      alice = create_trusted_user("gm_alice3", "gm_alice3@example.com")
      bob = create_trusted_user("gm_bob3", "gm_bob3@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "Delete me"})
      {:ok, _} = Messaging.delete_message(msg.id, alice.id)

      assert {:ok, messages} = Messaging.get_messages(conv.id, alice.id)
      assert length(messages) == 0
    end
  end

  describe "mark_read/2" do
    test "marks conversation as read" do
      alice = create_trusted_user("mr_alice", "mr_alice@example.com")
      bob = create_trusted_user("mr_bob", "mr_bob@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})

      assert {:ok, _} = Messaging.mark_read(conv.id, bob.id)

      # Verify last_read_message_id is set
      participant =
        Hybridsocial.Messaging.Participant
        |> where([p], p.conversation_id == ^conv.id and p.identity_id == ^bob.id)
        |> Repo.one()

      assert participant.last_read_message_id == msg.id
    end
  end

  describe "unread_count/2" do
    test "counts unread messages" do
      alice = create_trusted_user("uc_alice", "uc_alice@example.com")
      bob = create_trusted_user("uc_bob", "uc_bob@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, _} = Messaging.send_message(conv.id, alice.id, %{"content" => "Message 1"})
      {:ok, _} = Messaging.send_message(conv.id, alice.id, %{"content" => "Message 2"})

      assert {:ok, 2} = Messaging.unread_count(conv.id, bob.id)
    end

    test "returns 0 after marking read" do
      alice = create_trusted_user("uc_alice2", "uc_alice2@example.com")
      bob = create_trusted_user("uc_bob2", "uc_bob2@example.com")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, _} = Messaging.send_message(conv.id, alice.id, %{"content" => "Hello!"})
      {:ok, _} = Messaging.mark_read(conv.id, bob.id)

      assert {:ok, 0} = Messaging.unread_count(conv.id, bob.id)
    end
  end

  # ---------------------------------------------------------------------------
  # DM Preferences
  # ---------------------------------------------------------------------------

  describe "DM preferences" do
    test "returns defaults when not set" do
      alice = create_trusted_user("dp_alice", "dp_alice@example.com")

      {:ok, pref} = Messaging.get_dm_preferences(alice.id)
      assert pref.allow_dms_from == "everyone"
      assert pref.allow_group_dms == false
    end

    test "updates preferences" do
      alice = create_trusted_user("dp_alice2", "dp_alice2@example.com")

      {:ok, pref} =
        Messaging.update_dm_preferences(alice.id, %{
          "allow_dms_from" => "followers",
          "allow_group_dms" => true
        })

      assert pref.allow_dms_from == "followers"
      assert pref.allow_group_dms == true
    end

    test "updates existing preferences" do
      alice = create_trusted_user("dp_alice3", "dp_alice3@example.com")

      {:ok, _} = Messaging.update_dm_preferences(alice.id, %{"allow_dms_from" => "followers"})
      {:ok, pref} = Messaging.update_dm_preferences(alice.id, %{"allow_dms_from" => "nobody"})

      assert pref.allow_dms_from == "nobody"
    end
  end

  describe "can_dm?/2" do
    test "allows DM when preference is everyone" do
      alice = create_trusted_user("cd_alice", "cd_alice@example.com")
      bob = create_trusted_user("cd_bob", "cd_bob@example.com")

      assert Messaging.can_dm?(alice.id, bob.id) == true
    end

    test "blocks DM when preference is nobody" do
      alice = create_trusted_user("cd_alice2", "cd_alice2@example.com")
      bob = create_trusted_user("cd_bob2", "cd_bob2@example.com")

      {:ok, _} = Messaging.update_dm_preferences(bob.id, %{"allow_dms_from" => "nobody"})

      assert Messaging.can_dm?(alice.id, bob.id) == false
    end

    test "allows DM when preference is followers and recipient follows sender" do
      alice = create_trusted_user("cd_alice3", "cd_alice3@example.com")
      bob = create_trusted_user("cd_bob3", "cd_bob3@example.com")

      {:ok, _} = Messaging.update_dm_preferences(bob.id, %{"allow_dms_from" => "followers"})
      {:ok, _} = Hybridsocial.Social.follow(bob.id, alice.id)

      assert Messaging.can_dm?(alice.id, bob.id) == true
    end

    test "blocks DM when preference is followers and recipient does not follow sender" do
      alice = create_trusted_user("cd_alice4", "cd_alice4@example.com")
      bob = create_trusted_user("cd_bob4", "cd_bob4@example.com")

      {:ok, _} = Messaging.update_dm_preferences(bob.id, %{"allow_dms_from" => "followers"})

      assert Messaging.can_dm?(alice.id, bob.id) == false
    end

    test "blocks DM when either user has blocked the other" do
      alice = create_trusted_user("cd_alice5", "cd_alice5@example.com")
      bob = create_trusted_user("cd_bob5", "cd_bob5@example.com")

      {:ok, _} = Hybridsocial.Social.block(alice.id, bob.id)

      assert Messaging.can_dm?(alice.id, bob.id) == false
      assert Messaging.can_dm?(bob.id, alice.id) == false
    end

    test "allows DM when preference is mutual_followers and both follow each other" do
      alice = create_trusted_user("cd_alice6", "cd_alice6@example.com")
      bob = create_trusted_user("cd_bob6", "cd_bob6@example.com")

      {:ok, _} =
        Messaging.update_dm_preferences(bob.id, %{"allow_dms_from" => "mutual_followers"})

      {:ok, _} = Hybridsocial.Social.follow(bob.id, alice.id)
      {:ok, _} = Hybridsocial.Social.follow(alice.id, bob.id)

      assert Messaging.can_dm?(alice.id, bob.id) == true
    end

    test "blocks DM when preference is mutual_followers but only one follows" do
      alice = create_trusted_user("cd_alice7", "cd_alice7@example.com")
      bob = create_trusted_user("cd_bob7", "cd_bob7@example.com")

      {:ok, _} =
        Messaging.update_dm_preferences(bob.id, %{"allow_dms_from" => "mutual_followers"})

      {:ok, _} = Hybridsocial.Social.follow(bob.id, alice.id)

      assert Messaging.can_dm?(alice.id, bob.id) == false
    end
  end

  describe "edit_message/3 — 5-minute window" do
    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
      start_supervised!(Hybridsocial.Config.Store)
      :ok
    end

    test "succeeds within the window" do
      alice = create_trusted_user("em_a", "em_a@example.com")
      bob = create_trusted_user("em_b", "em_b@example.com")
      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "first draft"})

      assert {:ok, edited} = Messaging.edit_message(msg.id, alice.id, "second draft")
      assert edited.content == "second draft"
      assert edited.edited_at != nil
    end

    test "rejects after the configured window has elapsed" do
      alice = create_trusted_user("em_a2", "em_a2@example.com")
      bob = create_trusted_user("em_b2", "em_b2@example.com")
      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "old"})

      backdated = DateTime.add(DateTime.utc_now(), -10 * 60, :second)

      Hybridsocial.Repo.update_all(
        Ecto.Query.from(m in Hybridsocial.Messaging.Message, where: m.id == ^msg.id),
        set: [created_at: backdated]
      )

      assert {:error, :edit_window_expired} =
               Messaging.edit_message(msg.id, alice.id, "trying anyway")
    end

    test "respects an admin-changed window via dm_edit_window_seconds config" do
      alice = create_trusted_user("em_a3", "em_a3@example.com")
      bob = create_trusted_user("em_b3", "em_b3@example.com")
      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "x"})

      Hybridsocial.Config.set("dm_edit_window_seconds", 1)
      backdated = DateTime.add(DateTime.utc_now(), -5, :second)

      Hybridsocial.Repo.update_all(
        Ecto.Query.from(m in Hybridsocial.Messaging.Message, where: m.id == ^msg.id),
        set: [created_at: backdated]
      )

      assert {:error, :edit_window_expired} =
               Messaging.edit_message(msg.id, alice.id, "y")
    end

    test "rejects edit attempts from non-senders" do
      alice = create_trusted_user("em_a4", "em_a4@example.com")
      bob = create_trusted_user("em_b4", "em_b4@example.com")
      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "alice's"})

      assert {:error, :forbidden} = Messaging.edit_message(msg.id, bob.id, "stolen")
    end
  end

  defp opt_into_group_dms(identity, extra \\ %{}) do
    {:ok, _} =
      Messaging.update_dm_preferences(identity.id, Map.put(extra, "allow_group_dms", true))
  end
end

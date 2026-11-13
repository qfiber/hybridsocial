defmodule Hybridsocial.Accounts.AccountDeletionTest do
  use Hybridsocial.DataCase, async: false

  import Hybridsocial.AccountsFixtures

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.AccountDeletion
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post
  alias Hybridsocial.Media.MediaFile
  alias Hybridsocial.Messaging
  alias Hybridsocial.Messaging.{Conversation, Message}
  alias HybridsocialWeb.Helpers.Account, as: AccountHelper

  defp media_fixture(identity_id, attrs \\ %{}) do
    %MediaFile{}
    |> MediaFile.create_changeset(
      Map.merge(
        %{
          "identity_id" => identity_id,
          "content_type" => "image/jpeg",
          "file_size" => 123,
          "storage_path" => "test/#{Ecto.UUID.generate()}.jpg"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "delete_account/1" do
    test "hard-deletes the account's posts and replies, keeps others'" do
      target = create_user("target_del")
      other = create_user("bystander_del")

      {:ok, post} = Hybridsocial.Social.Posts.create_post(target.id, %{"content" => "mine"})

      {:ok, _reply} =
        Hybridsocial.Social.Posts.create_post(target.id, %{"content" => "also mine"})

      {:ok, kept} = Hybridsocial.Social.Posts.create_post(other.id, %{"content" => "not mine"})

      assert {:ok, summary} = AccountDeletion.delete_account(target)
      assert summary.posts_deleted == 2

      assert Repo.get(Post, post.id) == nil
      refute Repo.get(Post, kept.id) == nil
    end

    test "deletes media owned by the account" do
      target = create_user("media_del")
      m = media_fixture(target.id)

      assert {:ok, summary} = AccountDeletion.delete_account(target)
      assert summary.media_deleted >= 1
      assert Repo.get(MediaFile, m.id) == nil
    end

    test "soft-deletes the identity and renders it as \"Deleted User\"" do
      target = create_user("soft_del")

      assert {:ok, _} = AccountDeletion.delete_account(target)

      # Ordinary lookup no longer finds it...
      assert Accounts.get_identity(target.id) == nil
      # ...but the row survives for DM history and renders scrubbed.
      reloaded = Accounts.get_identity_including_deleted(target.id)
      refute is_nil(reloaded.deleted_at)

      summary = AccountHelper.serialize_summary(reloaded)
      assert summary.display_name == "Deleted User"
      assert summary.handle == "deleted"
      assert summary.avatar_url == nil
    end

    test "keeps a DM when the other participant survives" do
      alice = create_trusted_user("dm_alice")
      bob = create_trusted_user("dm_bob")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, _msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "hi bob"})

      assert {:ok, summary} = AccountDeletion.delete_account(alice)
      assert summary.conversations_dropped == 0

      # Conversation and its message are still there for Bob.
      refute Repo.get(Conversation, conv.id) == nil
      assert Repo.aggregate(from(m in Message, where: m.conversation_id == ^conv.id), :count) == 1
    end

    test "drops a DM once both participants are deleted" do
      alice = create_trusted_user("dead_alice")
      bob = create_trusted_user("dead_bob")

      {:ok, conv} = Messaging.find_or_create_direct(alice.id, bob.id)
      {:ok, _msg} = Messaging.send_message(conv.id, alice.id, %{"content" => "hi"})

      {:ok, _} = AccountDeletion.delete_account(alice)
      assert Repo.get(Conversation, conv.id) != nil

      assert {:ok, summary} = AccountDeletion.delete_account(bob)
      assert summary.conversations_dropped == 1
      assert Repo.get(Conversation, conv.id) == nil
      assert Repo.aggregate(from(m in Message, where: m.conversation_id == ^conv.id), :count) == 0
    end
  end
end

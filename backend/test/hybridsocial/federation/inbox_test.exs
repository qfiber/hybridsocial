defmodule Hybridsocial.Federation.InboxTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Federation.Inbox
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social
  alias Hybridsocial.Social.{Post, Posts}

  # Helper to create a local identity
  defp create_local_identity(handle \\ "localuser") do
    %Identity{}
    |> Identity.create_changeset(%{
      "type" => "user",
      "handle" => handle,
      "display_name" => "Local User"
    })
    |> Repo.insert!()
  end

  # Helper to create a remote identity stub
  defp create_remote_identity(ap_id, handle) do
    id = Ecto.UUID.generate()

    %Identity{}
    |> Ecto.Changeset.cast(
      %{
        id: id,
        type: "user",
        handle: handle,
        ap_actor_url: ap_id,
        inbox_url: "#{ap_id}/inbox",
        outbox_url: "#{ap_id}/outbox",
        followers_url: "#{ap_id}/followers"
      },
      [:id, :type, :handle, :ap_actor_url, :inbox_url, :outbox_url, :followers_url]
    )
    |> Ecto.Changeset.validate_required([:type, :handle])
    |> Ecto.Changeset.unique_constraint(:handle)
    |> Repo.insert!()
  end

  # Helper to create a local post
  defp create_local_post(identity) do
    {:ok, post} =
      Posts.create_post(identity.id, %{
        "content" => "Hello from local!",
        "post_type" => "text",
        "visibility" => "public"
      })

    post
  end

  defp base_url, do: HybridsocialWeb.Endpoint.url()

  describe "process/1 - Follow" do
    test "creates a follow relationship for a valid Follow activity" do
      local = create_local_identity("follow_target")
      remote_ap_id = "https://remote.example/users/alice"

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/follow-1",
        "type" => "Follow",
        "actor" => remote_ap_id,
        "object" => "#{base_url()}/actors/#{local.id}"
      }

      assert {:ok, %{follow: follow}} = Inbox.process(activity)
      assert follow.followee_id == local.id
      assert follow.status == :accepted
    end

    test "creates a pending follow for a locked account" do
      local =
        %Identity{}
        |> Identity.create_changeset(%{
          "type" => "user",
          "handle" => "locked_user",
          "is_locked" => true
        })
        |> Repo.insert!()

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/follow-2",
        "type" => "Follow",
        "actor" => "https://remote.example/users/bob",
        "object" => "#{base_url()}/actors/#{local.id}"
      }

      assert {:ok, %{follow: follow}} = Inbox.process(activity)
      assert follow.status == :pending
    end

    test "returns error for invalid follow activity" do
      assert {:error, :invalid_follow_activity} = Inbox.process(%{"type" => "Follow"})
    end
  end

  describe "process/1 - Accept" do
    test "accepts a pending follow" do
      local = create_local_identity("accept_follower")
      remote = create_remote_identity("https://remote.example/users/charlie", "charlie_remote")

      # Create a pending follow (local follows remote)
      {:ok, _follow} =
        %Social.Follow{}
        |> Social.Follow.changeset(%{
          follower_id: local.id,
          followee_id: remote.id,
          status: :pending
        })
        |> Repo.insert()

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/accept-1",
        "type" => "Accept",
        "actor" => remote.ap_actor_url,
        "object" => %{
          "type" => "Follow",
          "id" => "https://local.example/activities/follow-orig",
          "actor" => "#{base_url()}/actors/#{local.id}",
          "object" => remote.ap_actor_url
        }
      }

      assert {:ok, accepted_follow} = Inbox.process(activity)
      assert accepted_follow.status == :accepted
    end
  end

  describe "process/1 - Reject" do
    test "rejects a pending follow" do
      local = create_local_identity("reject_follower")
      remote = create_remote_identity("https://remote.example/users/dave", "dave_remote")

      {:ok, _follow} =
        %Social.Follow{}
        |> Social.Follow.changeset(%{
          follower_id: local.id,
          followee_id: remote.id,
          status: :pending
        })
        |> Repo.insert()

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/reject-1",
        "type" => "Reject",
        "actor" => remote.ap_actor_url,
        "object" => %{
          "type" => "Follow",
          "id" => "https://local.example/activities/follow-orig-2",
          "actor" => "#{base_url()}/actors/#{local.id}",
          "object" => remote.ap_actor_url
        }
      }

      assert {:ok, rejected_follow} = Inbox.process(activity)
      assert rejected_follow.status == :rejected
    end
  end

  describe "process/1 - Create" do
    test "creates a local post for a remote Note" do
      remote_ap_id = "https://remote.example/users/eve"

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/create-1",
        "type" => "Create",
        "actor" => remote_ap_id,
        "object" => %{
          "id" => "https://remote.example/objects/note-1",
          "type" => "Note",
          "content" => "<p>Hello from remote!</p>",
          "attributedTo" => remote_ap_id,
          "published" => "2026-03-22T10:00:00Z",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => ["https://remote.example/users/eve/followers"]
        }
      }

      assert {:ok, post} = Inbox.process(activity)
      assert post.content_html == "<p>Hello from remote!</p>"
      assert post.ap_id == "https://remote.example/objects/note-1"
      assert post.visibility == "public"
    end

    test "does not create duplicate posts" do
      remote_ap_id = "https://remote.example/users/frank"

      object = %{
        "id" => "https://remote.example/objects/note-dup",
        "type" => "Note",
        "content" => "Duplicate test",
        "attributedTo" => remote_ap_id,
        "published" => "2026-03-22T11:00:00Z",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"]
      }

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/create-dup",
        "type" => "Create",
        "actor" => remote_ap_id,
        "object" => object
      }

      assert {:ok, post1} = Inbox.process(activity)
      assert {:ok, post2} = Inbox.process(activity)
      assert post1.id == post2.id
    end

    test "returns error when object is a string reference" do
      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/create-ref",
        "type" => "Create",
        "actor" => "https://remote.example/users/grace",
        "object" => "https://remote.example/objects/note-ref"
      }

      assert {:error, :object_must_be_embedded} = Inbox.process(activity)
    end
  end

  describe "process/1 - Like" do
    test "creates a like reaction on a local post" do
      local = create_local_identity("like_target")
      post = create_local_post(local)
      remote = create_remote_identity("https://remote.example/users/hank", "hank_remote")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/like-1",
        "type" => "Like",
        "actor" => remote.ap_actor_url,
        "object" => "#{base_url()}/objects/#{post.id}"
      }

      assert {:ok, reaction} = Inbox.process(activity)
      assert reaction.type == "like"
      assert reaction.post_id == post.id
    end
  end

  describe "process/1 - EmojiReact" do
    test "creates a reaction with mapped emoji type" do
      local = create_local_identity("emoji_target")
      post = create_local_post(local)
      remote = create_remote_identity("https://remote.example/users/iris", "iris_remote")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/react-1",
        "type" => "EmojiReact",
        "actor" => remote.ap_actor_url,
        "object" => "#{base_url()}/objects/#{post.id}",
        "content" => "\u2764\uFE0F"
      }

      assert {:ok, reaction} = Inbox.process(activity)
      assert reaction.type == "love"
    end
  end

  describe "process/1 - Announce" do
    test "creates a boost on a local post" do
      local = create_local_identity("boost_target")
      post = create_local_post(local)
      remote = create_remote_identity("https://remote.example/users/jake", "jake_remote")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/announce-1",
        "type" => "Announce",
        "actor" => remote.ap_actor_url,
        "object" => "#{base_url()}/objects/#{post.id}"
      }

      assert {:ok, boost} = Inbox.process(activity)
      assert boost.post_id == post.id
    end
  end

  describe "process/1 - Delete" do
    test "soft-deletes a remote post" do
      remote = create_remote_identity("https://remote.example/users/kate", "kate_remote")

      # Create a post attributed to the remote identity
      {:ok, _post} =
        %Post{}
        |> Post.create_changeset(%{
          "content" => "To be deleted",
          "identity_id" => remote.id,
          "ap_id" => "https://remote.example/objects/delete-me"
        })
        |> Ecto.Changeset.put_change(
          :published_at,
          DateTime.utc_now() |> DateTime.truncate(:microsecond)
        )
        |> Ecto.Changeset.put_change(
          :edit_expires_at,
          DateTime.add(DateTime.utc_now(), 86400, :second) |> DateTime.truncate(:microsecond)
        )
        |> Repo.insert()

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/delete-1",
        "type" => "Delete",
        "actor" => remote.ap_actor_url,
        "object" => "https://remote.example/objects/delete-me"
      }

      assert {:ok, deleted_post} = Inbox.process(activity)
      assert deleted_post.deleted_at != nil
    end

    test "returns :already_deleted for unknown posts" do
      remote = create_remote_identity("https://remote.example/users/lee", "lee_remote")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/delete-2",
        "type" => "Delete",
        "actor" => remote.ap_actor_url,
        "object" => "https://remote.example/objects/nonexistent"
      }

      assert {:ok, :already_deleted} = Inbox.process(activity)
    end
  end

  describe "process/1 - Update" do
    test "updates a remote actor's identity" do
      remote = create_remote_identity("https://remote.example/users/mike", "mike_remote")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/update-1",
        "type" => "Update",
        "actor" => remote.ap_actor_url,
        "object" => %{
          "id" => remote.ap_actor_url,
          "type" => "Person",
          "name" => "Mike Updated",
          "preferredUsername" => "mike",
          "inbox" => "#{remote.ap_actor_url}/inbox"
        }
      }

      assert {:ok, updated} = Inbox.process(activity)
      assert updated.display_name == "Mike Updated"
    end
  end

  describe "process/1 - Block" do
    test "creates a block relationship" do
      local = create_local_identity("block_target")
      remote = create_remote_identity("https://remote.example/users/nancy", "nancy_remote")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/block-1",
        "type" => "Block",
        "actor" => remote.ap_actor_url,
        "object" => "#{base_url()}/actors/#{local.id}"
      }

      assert {:ok, _block} = Inbox.process(activity)
      assert Social.blocked?(remote.id, local.id)
    end
  end

  describe "process/1 - Undo" do
    test "undoes a follow" do
      local = create_local_identity("undo_follow_target")
      remote = create_remote_identity("https://remote.example/users/otto", "otto_remote")

      # Create a follow first
      {:ok, _follow} = Social.follow(remote.id, local.id)
      assert Social.following?(remote.id, local.id)

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/undo-1",
        "type" => "Undo",
        "actor" => remote.ap_actor_url,
        "object" => %{
          "type" => "Follow",
          "id" => "https://remote.example/activities/follow-orig",
          "actor" => remote.ap_actor_url,
          "object" => "#{base_url()}/actors/#{local.id}"
        }
      }

      assert {:ok, :unfollowed} = Inbox.process(activity)
      refute Social.following?(remote.id, local.id)
    end

    test "undoes a like" do
      local = create_local_identity("undo_like_target")
      post = create_local_post(local)
      remote = create_remote_identity("https://remote.example/users/pat", "pat_remote")

      # Create a like first
      {:ok, _reaction} = Posts.react(post.id, remote.id, "like")

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/undo-2",
        "type" => "Undo",
        "actor" => remote.ap_actor_url,
        "object" => %{
          "type" => "Like",
          "id" => "https://remote.example/activities/like-orig",
          "actor" => remote.ap_actor_url,
          "object" => "#{base_url()}/objects/#{post.id}"
        }
      }

      assert {:ok, _} = Inbox.process(activity)
    end

    test "undoes a boost" do
      local = create_local_identity("undo_boost_target")
      post = create_local_post(local)
      remote = create_remote_identity("https://remote.example/users/quinn", "quinn_remote")

      {:ok, _boost} = Posts.boost(post.id, remote.id)

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/undo-3",
        "type" => "Undo",
        "actor" => remote.ap_actor_url,
        "object" => %{
          "type" => "Announce",
          "id" => "https://remote.example/activities/announce-orig",
          "actor" => remote.ap_actor_url,
          "object" => "#{base_url()}/objects/#{post.id}"
        }
      }

      assert {:ok, _} = Inbox.process(activity)
    end

    test "undoes a block" do
      local = create_local_identity("undo_block_target")
      remote = create_remote_identity("https://remote.example/users/rosa", "rosa_remote")

      {:ok, _block} = Social.block(remote.id, local.id)
      assert Social.blocked?(remote.id, local.id)

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/undo-4",
        "type" => "Undo",
        "actor" => remote.ap_actor_url,
        "object" => %{
          "type" => "Block",
          "id" => "https://remote.example/activities/block-orig",
          "actor" => remote.ap_actor_url,
          "object" => "#{base_url()}/actors/#{local.id}"
        }
      }

      assert {:ok, :unblocked} = Inbox.process(activity)
      refute Social.blocked?(remote.id, local.id)
    end
  end

  describe "process/1 - invalid" do
    test "returns error for unsupported activity type" do
      assert {:error, :unsupported_activity_type} =
               Inbox.process(%{"type" => "Dislike", "actor" => "https://example.com/u/test"})
    end

    test "returns error for invalid activity" do
      assert {:error, :invalid_activity} = Inbox.process(%{})
    end
  end
end

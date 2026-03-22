defmodule Hybridsocial.Federation.ActivityBuilderTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Federation.ActivityBuilder
  alias Hybridsocial.Social.Posts

  @public "https://www.w3.org/ns/activitystreams#Public"

  describe "build_create/1" do
    test "builds a Create{Note} activity for a public post" do
      identity = create_user("alice", "alice@example.com")

      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "Hello world! #elixir",
          "visibility" => "public"
        })

      post = Hybridsocial.Repo.preload(post, :identity)
      activity = ActivityBuilder.build_create(post)

      assert activity["@context"] == "https://www.w3.org/ns/activitystreams"
      assert activity["type"] == "Create"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert String.contains?(activity["id"], "/activities/#{identity.id}/create/#{post.id}/")
      assert activity["published"] != nil

      # Check Note object
      note = activity["object"]
      assert note["type"] == "Note"
      assert note["id"] == "http://localhost:4002/posts/#{post.id}"
      assert note["attributedTo"] == "http://localhost:4002/actors/#{identity.id}"
      assert note["content"] != nil
      assert note["url"] == "http://localhost:4002/posts/#{post.id}"
      assert note["sensitive"] == false
      assert note["inReplyTo"] == nil

      # Check addressing for public post
      assert @public in note["to"]
      assert "http://localhost:4002/actors/#{identity.id}/followers" in note["cc"]

      # Check hashtag extraction
      tags = note["tag"]
      assert length(tags) == 1
      [tag] = tags
      assert tag["type"] == "Hashtag"
      assert tag["name"] == "#elixir"
    end

    test "builds a Create{Note} activity for a followers-only post" do
      identity = create_user("bob", "bob@example.com")

      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "Followers only",
          "visibility" => "followers"
        })

      post = Hybridsocial.Repo.preload(post, :identity)
      activity = ActivityBuilder.build_create(post)

      note = activity["object"]
      followers_url = "http://localhost:4002/actors/#{identity.id}/followers"

      assert note["to"] == [followers_url]
      assert note["cc"] == []
    end

    test "builds a Create{Note} activity for a direct post" do
      identity = create_user("carol", "carol@example.com")

      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "DM",
          "visibility" => "direct"
        })

      post = Hybridsocial.Repo.preload(post, :identity)
      activity = ActivityBuilder.build_create(post)

      note = activity["object"]
      assert note["to"] == []
      assert note["cc"] == []
    end

    test "includes spoiler text when present" do
      identity = create_user("dave", "dave@example.com")

      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "Spoiler content",
          "visibility" => "public",
          "sensitive" => true,
          "spoiler_text" => "Content warning"
        })

      post = Hybridsocial.Repo.preload(post, :identity)
      activity = ActivityBuilder.build_create(post)

      note = activity["object"]
      assert note["sensitive"] == true
      assert note["summary"] == "Content warning"
    end

    test "includes inReplyTo for reply posts" do
      identity = create_user("eve", "eve@example.com")

      {:ok, parent} =
        Posts.create_post(identity.id, %{
          "content" => "Parent post",
          "visibility" => "public"
        })

      {:ok, reply} =
        Posts.create_post(identity.id, %{
          "content" => "Reply post",
          "visibility" => "public",
          "parent_id" => parent.id,
          "root_id" => parent.id
        })

      reply = Hybridsocial.Repo.preload(reply, :identity)
      activity = ActivityBuilder.build_create(reply)

      note = activity["object"]
      assert note["inReplyTo"] == "http://localhost:4002/posts/#{parent.id}"
    end
  end

  describe "build_update/1" do
    test "builds an Update{Note} activity" do
      identity = create_user("frank", "frank@example.com")

      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "Original",
          "visibility" => "public"
        })

      post = Hybridsocial.Repo.preload(post, :identity)
      activity = ActivityBuilder.build_update(post)

      assert activity["type"] == "Update"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert String.contains?(activity["id"], "/activities/#{identity.id}/update/#{post.id}/")
      assert activity["object"]["type"] == "Note"
    end
  end

  describe "build_delete/1" do
    test "builds a Delete activity with Tombstone" do
      identity = create_user("grace", "grace@example.com")

      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "To be deleted",
          "visibility" => "public"
        })

      post = Hybridsocial.Repo.preload(post, :identity)
      activity = ActivityBuilder.build_delete(post)

      assert activity["type"] == "Delete"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["object"]["type"] == "Tombstone"
      assert activity["object"]["id"] == "http://localhost:4002/posts/#{post.id}"
      assert @public in activity["to"]
    end
  end

  describe "build_follow/2" do
    test "builds a Follow activity" do
      identity = create_user("henry", "henry@example.com")
      followee_ap_id = "https://remote.example/actors/remote-user"

      activity = ActivityBuilder.build_follow(identity, followee_ap_id)

      assert activity["type"] == "Follow"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["object"] == followee_ap_id
      assert String.contains?(activity["id"], "/activities/#{identity.id}/follow/")
    end
  end

  describe "build_accept_follow/2" do
    test "builds an Accept{Follow} activity" do
      identity = create_user("iris", "iris@example.com")
      follow_id = "https://remote.example/activities/some-uuid/follow/another-uuid/123"

      activity = ActivityBuilder.build_accept_follow(identity, follow_id)

      assert activity["type"] == "Accept"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["object"] == follow_id
    end
  end

  describe "build_reject_follow/2" do
    test "builds a Reject{Follow} activity" do
      identity = create_user("julia", "julia@example.com")
      follow_id = "https://remote.example/activities/some-uuid/follow/another-uuid/123"

      activity = ActivityBuilder.build_reject_follow(identity, follow_id)

      assert activity["type"] == "Reject"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["object"] == follow_id
    end
  end

  describe "build_like/2" do
    test "builds a Like activity" do
      identity = create_user("kate", "kate@example.com")
      other = create_user("liam", "liam@example.com")

      {:ok, post} =
        Posts.create_post(other.id, %{
          "content" => "Likeable post",
          "visibility" => "public"
        })

      activity = ActivityBuilder.build_like(identity, post)

      assert activity["type"] == "Like"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["object"] == "http://localhost:4002/posts/#{post.id}"
    end
  end

  describe "build_announce/2" do
    test "builds an Announce activity" do
      identity = create_user("mike", "mike@example.com")
      other = create_user("nina", "nina@example.com")

      {:ok, post} =
        Posts.create_post(other.id, %{
          "content" => "Boostable post",
          "visibility" => "public"
        })

      post = Hybridsocial.Repo.preload(post, :identity)
      activity = ActivityBuilder.build_announce(identity, post)

      assert activity["type"] == "Announce"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["object"] == "http://localhost:4002/posts/#{post.id}"
      assert @public in activity["to"]
      assert "http://localhost:4002/actors/#{identity.id}/followers" in activity["cc"]
      assert "http://localhost:4002/actors/#{other.id}" in activity["cc"]
    end
  end

  describe "build_undo/2" do
    test "builds an Undo wrapper" do
      identity = create_user("oscar", "oscar@example.com")

      inner_activity = %{
        "id" => "http://localhost:4002/activities/#{identity.id}/follow/some-uuid/123",
        "type" => "Follow",
        "actor" => "http://localhost:4002/actors/#{identity.id}",
        "object" => "https://remote.example/actors/remote-user"
      }

      activity = ActivityBuilder.build_undo(identity, inner_activity)

      assert activity["type"] == "Undo"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["object"] == inner_activity
    end
  end

  describe "build_block/2" do
    test "builds a Block activity" do
      identity = create_user("pat", "pat@example.com")
      target_ap_id = "https://remote.example/actors/blocked-user"

      activity = ActivityBuilder.build_block(identity, target_ap_id)

      assert activity["type"] == "Block"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["object"] == target_ap_id
    end
  end

  describe "build_move/2" do
    test "builds a Move activity" do
      identity = create_user("quinn", "quinn@example.com")
      new_ap_id = "https://new-server.example/actors/quinn"

      activity = ActivityBuilder.build_move(identity, new_ap_id)

      assert activity["type"] == "Move"
      assert activity["actor"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["object"] == "http://localhost:4002/actors/#{identity.id}"
      assert activity["target"] == new_ap_id
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

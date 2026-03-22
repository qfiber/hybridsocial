defmodule Hybridsocial.Social.PostsTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Social.Posts

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

  describe "create_post/2" do
    test "creates a post with valid attrs" do
      identity = create_user("poster", "poster@test.com")

      assert {:ok, post} =
               Posts.create_post(identity.id, %{
                 "content" => "Hello world!",
                 "visibility" => "public"
               })

      assert post.content == "Hello world!"
      assert post.visibility == "public"
      assert post.identity_id == identity.id
      assert post.published_at != nil
      assert post.edit_expires_at != nil
    end

    test "generates content_html from content" do
      identity = create_user("htmluser", "html@test.com")

      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "Hello <script>alert('xss')</script>"
        })

      assert post.content_html =~ "&lt;script&gt;"
      refute post.content_html =~ "<script>"
    end

    test "fails without content for text post" do
      identity = create_user("nopost", "nopost@test.com")

      assert {:error, changeset} =
               Posts.create_post(identity.id, %{"visibility" => "public"})

      assert errors_on(changeset)[:content] != nil
    end

    test "allows media post without content" do
      identity = create_user("mediauser", "media@test.com")

      assert {:ok, post} =
               Posts.create_post(identity.id, %{
                 "post_type" => "media",
                 "visibility" => "public"
               })

      assert post.post_type == "media"
    end

    test "extracts and links hashtags" do
      identity = create_user("hashuser", "hash@test.com")

      {:ok, post} =
        Posts.create_post(identity.id, %{
          "content" => "Hello #elixir and #phoenix!"
        })

      assert post.content =~ "#elixir"

      hashtags =
        Hybridsocial.Repo.all(
          from h in Hybridsocial.Social.Hashtag,
            where: h.name in ["elixir", "phoenix"]
        )

      assert length(hashtags) == 2
    end

    test "creates reply with parent_id" do
      identity = create_user("replier", "reply@test.com")
      {:ok, parent} = Posts.create_post(identity.id, %{"content" => "Parent post"})

      {:ok, reply} =
        Posts.create_post(identity.id, %{
          "content" => "Reply post",
          "parent_id" => parent.id,
          "root_id" => parent.id
        })

      assert reply.parent_id == parent.id
      assert reply.root_id == parent.id
    end
  end

  describe "edit_post/3" do
    test "edits own post within edit window" do
      identity = create_user("editor", "editor@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Original"})

      assert {:ok, updated} =
               Posts.edit_post(post.id, identity.id, %{"content" => "Edited"})

      assert updated.content == "Edited"
      assert updated.edited_at != nil
    end

    test "creates revision on edit" do
      identity = create_user("revuser", "rev@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Version 1"})

      {:ok, _updated} =
        Posts.edit_post(post.id, identity.id, %{"content" => "Version 2"})

      revisions = Posts.get_revisions(post.id)
      assert length(revisions) == 1
      assert hd(revisions).content == "Version 1"
      assert hd(revisions).revision_number == 1
    end

    test "rejects editing another user's post" do
      user1 = create_user("owner1", "owner1@test.com")
      user2 = create_user("other1", "other1@test.com")

      {:ok, post} = Posts.create_post(user1.id, %{"content" => "My post"})

      assert {:error, :forbidden} =
               Posts.edit_post(post.id, user2.id, %{"content" => "Hacked"})
    end

    test "rejects editing after edit window expires" do
      identity = create_user("expired", "expired@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Original"})

      # Force expire the edit window
      past = DateTime.add(DateTime.utc_now(), -25 * 3600, :second)

      Hybridsocial.Repo.update_all(
        from(p in Hybridsocial.Social.Post, where: p.id == ^post.id),
        set: [edit_expires_at: past]
      )

      post = Posts.get_post!(post.id)

      assert {:error, changeset} =
               Posts.edit_post(post.id, identity.id, %{"content" => "Too late"})

      assert errors_on(changeset)[:edit_expires_at] != nil
    end
  end

  describe "delete_post/2" do
    test "soft deletes own post" do
      identity = create_user("deleter", "deleter@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "To delete"})

      assert {:ok, deleted} = Posts.delete_post(post.id, identity.id)
      assert deleted.deleted_at != nil
      assert Posts.get_post(post.id) == nil
    end

    test "rejects deleting another user's post" do
      user1 = create_user("owner2", "owner2@test.com")
      user2 = create_user("other2", "other2@test.com")

      {:ok, post} = Posts.create_post(user1.id, %{"content" => "My post"})

      assert {:error, :forbidden} = Posts.delete_post(post.id, user2.id)
    end
  end

  describe "get_post/1 and get_post!/1" do
    test "returns post by id" do
      identity = create_user("getter", "getter@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Find me"})

      assert found = Posts.get_post(post.id)
      assert found.id == post.id
    end

    test "returns nil for soft-deleted post" do
      identity = create_user("softdel", "softdel@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Gone"})
      Posts.delete_post(post.id, identity.id)

      assert Posts.get_post(post.id) == nil
    end
  end

  describe "get_post_with_context/1" do
    test "preloads identity and associations" do
      identity = create_user("ctxuser", "ctx@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Context test"})

      loaded = Posts.get_post_with_context(post.id)
      assert loaded.identity.handle == "ctxuser"
    end
  end

  describe "get_thread/1" do
    test "returns ancestors and descendants" do
      identity = create_user("threaduser", "thread@test.com")

      {:ok, root} = Posts.create_post(identity.id, %{"content" => "Root"})

      {:ok, reply1} =
        Posts.create_post(identity.id, %{
          "content" => "Reply 1",
          "parent_id" => root.id,
          "root_id" => root.id
        })

      {:ok, _reply2} =
        Posts.create_post(identity.id, %{
          "content" => "Reply 2",
          "parent_id" => reply1.id,
          "root_id" => root.id
        })

      assert {:ok, thread} = Posts.get_thread(reply1.id)
      assert length(thread.ancestors) >= 1
      assert length(thread.descendants) >= 1
    end
  end

  describe "react/3 and unreact/2" do
    test "adds a reaction" do
      identity = create_user("reactor", "reactor@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "React to me"})

      assert {:ok, reaction} = Posts.react(post.id, identity.id, "love")
      assert reaction.type == "love"

      updated = Posts.get_post!(post.id)
      assert updated.reaction_count == 1
    end

    test "changes reaction type" do
      identity = create_user("changer", "changer@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Change reaction"})

      {:ok, _} = Posts.react(post.id, identity.id, "like")
      {:ok, updated_reaction} = Posts.react(post.id, identity.id, "love")
      assert updated_reaction.type == "love"
    end

    test "removes a reaction" do
      identity = create_user("unreactor", "unreactor@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Unreact me"})

      {:ok, _} = Posts.react(post.id, identity.id, "like")
      assert {:ok, _} = Posts.unreact(post.id, identity.id)

      updated = Posts.get_post!(post.id)
      assert updated.reaction_count == 0
    end
  end

  describe "get_reactions/1" do
    test "lists reactions with actors" do
      identity = create_user("listreact", "listreact@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "List reactions"})
      {:ok, _} = Posts.react(post.id, identity.id, "like")

      reactions = Posts.get_reactions(post.id)
      assert length(reactions) == 1
      assert hd(reactions).identity.handle == "listreact"
    end
  end

  describe "boost/2 and unboost/2" do
    test "creates a boost" do
      identity = create_user("booster", "booster@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Boost me"})

      assert {:ok, boost} = Posts.boost(post.id, identity.id)
      assert boost.post_id == post.id

      updated = Posts.get_post!(post.id)
      assert updated.boost_count == 1
    end

    test "removes a boost" do
      identity = create_user("unbooster", "unbooster@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Unboost me"})

      {:ok, _} = Posts.boost(post.id, identity.id)
      assert {:ok, _} = Posts.unboost(post.id, identity.id)

      updated = Posts.get_post!(post.id)
      assert updated.boost_count == 0
    end
  end

  describe "quote_post/3" do
    test "creates a quote post" do
      identity = create_user("quoter", "quoter@test.com")
      {:ok, original} = Posts.create_post(identity.id, %{"content" => "Original"})

      assert {:ok, quote_post} =
               Posts.quote_post(identity.id, original.id, %{
                 "content" => "Quoting this"
               })

      assert quote_post.quote_id == original.id
    end
  end

  describe "pin_post/2 and unpin_post/2" do
    test "pins and unpins a post" do
      identity = create_user("pinner", "pinner@test.com")
      {:ok, post} = Posts.create_post(identity.id, %{"content" => "Pin me"})

      assert {:ok, pinned} = Posts.pin_post(post.id, identity.id)
      assert pinned.is_pinned == true

      assert {:ok, unpinned} = Posts.unpin_post(post.id, identity.id)
      assert unpinned.is_pinned == false
    end
  end

  describe "extract_hashtags/1" do
    test "extracts hashtags from content" do
      tags = Posts.extract_hashtags("Hello #world and #elixir!")
      assert "world" in tags
      assert "elixir" in tags
    end

    test "deduplicates and lowercases" do
      tags = Posts.extract_hashtags("#Elixir #elixir #ELIXIR")
      assert tags == ["elixir"]
    end

    test "returns empty list for nil" do
      assert Posts.extract_hashtags(nil) == []
    end
  end

  describe "posts_by_identity/2" do
    test "returns paginated posts" do
      identity = create_user("paguser", "pag@test.com")

      for i <- 1..5 do
        Posts.create_post(identity.id, %{"content" => "Post #{i}"})
      end

      result = Posts.posts_by_identity(identity.id, limit: 3)
      assert length(result.posts) == 3
      assert result.next_cursor != nil

      result2 = Posts.posts_by_identity(identity.id, limit: 3, cursor: result.next_cursor)
      assert length(result2.posts) == 2
    end
  end
end

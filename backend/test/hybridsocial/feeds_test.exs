defmodule Hybridsocial.FeedsTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Feeds
  alias Hybridsocial.Feeds.Visibility
  alias Hybridsocial.Social.{Post, Follow, Block, Mute, Boost}

  setup do
    try do
      Hybridsocial.Cache.flush_pattern("feed:*")
    rescue
      _ -> :ok
    end

    :ok
  end

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

  defp create_post(identity, attrs \\ %{}) do
    defaults = %{
      identity_id: identity.id,
      content: "Test post by #{identity.handle}",
      visibility: "public",
      post_type: "text"
    }

    %Post{}
    |> Post.create_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp create_follow(follower, followee, status \\ :accepted) do
    %Follow{}
    |> Follow.changeset(%{
      follower_id: follower.id,
      followee_id: followee.id,
      status: status
    })
    |> Repo.insert!()
  end

  defp create_block(blocker, blocked) do
    %Block{}
    |> Block.changeset(%{
      blocker_id: blocker.id,
      blocked_id: blocked.id
    })
    |> Repo.insert!()
  end

  defp create_mute(muter, muted) do
    %Mute{}
    |> Mute.changeset(%{
      muter_id: muter.id,
      muted_id: muted.id
    })
    |> Repo.insert!()
  end

  defp create_boost(identity, post) do
    %Boost{}
    |> Boost.changeset(%{
      identity_id: identity.id,
      post_id: post.id
    })
    |> Repo.insert!()
  end

  # ---------------------------------------------------------------------------
  # Home Timeline
  # ---------------------------------------------------------------------------

  describe "home_timeline/2" do
    test "returns posts from followed accounts" do
      alice = create_user("alice", "alice@example.com")
      bob = create_user("bob", "bob@example.com")
      carol = create_user("carol", "carol@example.com")

      create_follow(alice, bob)

      post_bob = create_post(bob, %{content: "Bob's post"})
      _post_carol = create_post(carol, %{content: "Carol's post"})

      entries = Feeds.home_timeline(alice.id)
      post_ids = Enum.map(entries, fn e -> e.data.id end)

      assert post_bob.id in post_ids
      refute Enum.any?(entries, fn e -> e.data.id == _post_carol.id end)
    end

    test "includes own posts" do
      alice = create_user("alice_own", "alice_own@example.com")
      post = create_post(alice, %{content: "My own post"})

      entries = Feeds.home_timeline(alice.id)
      post_ids = Enum.map(entries, fn e -> e.data.id end)

      assert post.id in post_ids
    end

    test "excludes soft-deleted posts" do
      alice = create_user("alice_del", "alice_del@example.com")
      bob = create_user("bob_del", "bob_del@example.com")
      create_follow(alice, bob)

      post = create_post(bob)

      post
      |> Post.soft_delete_changeset()
      |> Repo.update!()

      entries = Feeds.home_timeline(alice.id)
      assert entries == []
    end

    test "excludes posts from blocked accounts" do
      alice = create_user("alice_block", "alice_block@example.com")
      bob = create_user("bob_block", "bob_block@example.com")
      create_follow(alice, bob)
      create_post(bob)
      create_block(alice, bob)

      entries = Feeds.home_timeline(alice.id)
      assert entries == []
    end

    test "excludes posts from muted accounts" do
      alice = create_user("alice_mute", "alice_mute@example.com")
      bob = create_user("bob_mute", "bob_mute@example.com")
      create_follow(alice, bob)
      create_post(bob)
      create_mute(alice, bob)

      entries = Feeds.home_timeline(alice.id)
      assert entries == []
    end

    test "supports cursor pagination with max_id" do
      alice = create_user("alice_page", "alice_page@example.com")
      bob = create_user("bob_page", "bob_page@example.com")
      create_follow(alice, bob)

      post1 = create_post(bob, %{content: "Post 1"})
      post2 = create_post(bob, %{content: "Post 2"})

      # max_id filters by UUID comparison — get all entries first, then verify
      # that requesting with a specific max_id returns fewer results
      all_entries = Feeds.home_timeline(alice.id)
      all_ids = Enum.map(all_entries, fn e -> e.data.id end)

      assert post1.id in all_ids
      assert post2.id in all_ids

      # Using the "larger" UUID as max_id should exclude it
      [larger, smaller] = Enum.sort([post1.id, post2.id], :desc)
      entries = Feeds.home_timeline(alice.id, max_id: larger)
      filtered_ids = Enum.map(entries, fn e -> e.data.id end)

      assert smaller in filtered_ids
      refute larger in filtered_ids
    end

    test "respects limit option" do
      alice = create_user("alice_lim", "alice_lim@example.com")
      bob = create_user("bob_lim", "bob_lim@example.com")
      create_follow(alice, bob)

      for i <- 1..5 do
        create_post(bob, %{content: "Post #{i}"})
      end

      entries = Feeds.home_timeline(alice.id, limit: 3)
      assert length(entries) == 3
    end

    test "includes boosts from followed accounts" do
      alice = create_user("alice_boost", "alice_boost@example.com")
      bob = create_user("bob_boost", "bob_boost@example.com")
      carol = create_user("carol_boost", "carol_boost@example.com")
      create_follow(alice, bob)

      post = create_post(carol, %{content: "Carol's original"})
      _boost = create_boost(bob, post)

      entries = Feeds.home_timeline(alice.id)
      boost_entries = Enum.filter(entries, fn e -> e.type == :boost end)

      assert length(boost_entries) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # Public Timeline
  # ---------------------------------------------------------------------------

  describe "public_timeline/1" do
    test "returns only public posts" do
      alice = create_user("alice_pub", "alice_pub@example.com")
      public_post = create_post(alice, %{content: "Public", visibility: "public"})

      _private_post =
        create_post(alice, %{content: "Followers only", visibility: "followers"})

      posts = Feeds.public_timeline()
      ids = Enum.map(posts, & &1.id)

      assert public_post.id in ids
      refute _private_post.id in ids
    end

    test "excludes replies by default" do
      alice = create_user("alice_rep", "alice_rep@example.com")
      parent = create_post(alice, %{content: "Parent"})

      _reply =
        create_post(alice, %{content: "Reply", parent_id: parent.id, root_id: parent.id})

      posts = Feeds.public_timeline()
      ids = Enum.map(posts, & &1.id)

      assert parent.id in ids
      refute _reply.id in ids
    end

    test "includes replies when include_replies is true" do
      alice = create_user("alice_rep2", "alice_rep2@example.com")
      parent = create_post(alice, %{content: "Parent"})

      reply =
        create_post(alice, %{content: "Reply", parent_id: parent.id, root_id: parent.id})

      posts = Feeds.public_timeline(include_replies: true)
      ids = Enum.map(posts, & &1.id)

      assert parent.id in ids
      assert reply.id in ids
    end

    test "excludes soft-deleted posts" do
      alice = create_user("alice_pubdel", "alice_pubdel@example.com")
      post = create_post(alice)

      post
      |> Post.soft_delete_changeset()
      |> Repo.update!()

      posts = Feeds.public_timeline()
      ids = Enum.map(posts, & &1.id)

      refute post.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # Account Timeline
  # ---------------------------------------------------------------------------

  describe "account_timeline/3" do
    test "shows all posts when viewer is the account owner" do
      alice = create_user("alice_own_acct", "alice_own_acct@example.com")
      public_post = create_post(alice, %{content: "Public", visibility: "public"})

      followers_post =
        create_post(alice, %{content: "Followers", visibility: "followers"})

      posts = Feeds.account_timeline(alice.id, alice.id)
      ids = extract_post_ids(posts)

      assert public_post.id in ids
      assert followers_post.id in ids
    end

    test "shows public + followers posts when viewer follows account" do
      alice = create_user("alice_follower", "alice_follower@example.com")
      bob = create_user("bob_follower", "bob_follower@example.com")
      create_follow(bob, alice)

      public_post = create_post(alice, %{content: "Public", visibility: "public"})
      followers_post = create_post(alice, %{content: "Followers", visibility: "followers"})

      posts = Feeds.account_timeline(alice.id, bob.id)
      ids = extract_post_ids(posts)

      assert public_post.id in ids
      assert followers_post.id in ids
    end

    test "shows only public posts for non-followers" do
      alice = create_user("alice_nofol", "alice_nofol@example.com")
      bob = create_user("bob_nofol", "bob_nofol@example.com")

      public_post = create_post(alice, %{content: "Public", visibility: "public"})

      _followers_post =
        create_post(alice, %{content: "Followers", visibility: "followers"})

      posts = Feeds.account_timeline(alice.id, bob.id)
      ids = extract_post_ids(posts)

      assert public_post.id in ids
      refute _followers_post.id in ids
    end

    test "returns empty when viewer is blocked" do
      alice = create_user("alice_blk", "alice_blk@example.com")
      bob = create_user("bob_blk", "bob_blk@example.com")
      create_post(alice, %{content: "Blocked"})
      create_block(alice, bob)

      posts = Feeds.account_timeline(alice.id, bob.id)
      assert posts == []
    end

    test "shows only public posts for unauthenticated viewer" do
      alice = create_user("alice_anon", "alice_anon@example.com")
      public_post = create_post(alice, %{content: "Public", visibility: "public"})

      _followers_post =
        create_post(alice, %{content: "Followers", visibility: "followers"})

      posts = Feeds.account_timeline(alice.id)
      ids = extract_post_ids(posts)

      assert public_post.id in ids
      refute _followers_post.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # Hashtag Timeline
  # ---------------------------------------------------------------------------

  describe "hashtag_timeline/2" do
    test "returns public posts matching the hashtag" do
      alice = create_user("alice_tag", "alice_tag@example.com")
      tagged = create_post(alice, %{content: "Hello #elixir world"})
      _untagged = create_post(alice, %{content: "Hello world"})

      posts = Feeds.hashtag_timeline("elixir")
      ids = Enum.map(posts, & &1.id)

      assert tagged.id in ids
      refute _untagged.id in ids
    end

    test "only includes public posts" do
      alice = create_user("alice_tag2", "alice_tag2@example.com")

      _private =
        create_post(alice, %{
          content: "Hello #elixir",
          visibility: "followers"
        })

      posts = Feeds.hashtag_timeline("elixir")
      assert posts == []
    end
  end

  # ---------------------------------------------------------------------------
  # Visibility
  # ---------------------------------------------------------------------------

  describe "Visibility.visible_to?/2" do
    test "public posts are always visible" do
      alice = create_user("alice_vis", "alice_vis@example.com")
      bob = create_user("bob_vis", "bob_vis@example.com")
      post = create_post(alice, %{visibility: "public"})

      assert Visibility.visible_to?(post, bob.id)
    end

    test "author can always see own posts" do
      alice = create_user("alice_vis2", "alice_vis2@example.com")
      post = create_post(alice, %{visibility: "followers"})

      assert Visibility.visible_to?(post, alice.id)
    end

    test "followers posts visible to followers" do
      alice = create_user("alice_vis3", "alice_vis3@example.com")
      bob = create_user("bob_vis3", "bob_vis3@example.com")
      create_follow(bob, alice)
      post = create_post(alice, %{visibility: "followers"})

      assert Visibility.visible_to?(post, bob.id)
    end

    test "followers posts not visible to non-followers" do
      alice = create_user("alice_vis4", "alice_vis4@example.com")
      bob = create_user("bob_vis4", "bob_vis4@example.com")
      post = create_post(alice, %{visibility: "followers"})

      refute Visibility.visible_to?(post, bob.id)
    end

    test "not visible to nil viewer" do
      alice = create_user("alice_vis5", "alice_vis5@example.com")
      post = create_post(alice, %{visibility: "followers"})

      refute Visibility.visible_to?(post, nil)
    end

    test "group visibility returns true (stub)" do
      alice = create_user("alice_grp", "alice_grp@example.com")
      bob = create_user("bob_grp", "bob_grp@example.com")
      post = create_post(alice, %{visibility: "group"})

      assert Visibility.visible_to?(post, bob.id)
    end

    test "direct visibility returns false (stub)" do
      alice = create_user("alice_dm", "alice_dm@example.com")
      bob = create_user("bob_dm", "bob_dm@example.com")
      post = create_post(alice, %{visibility: "direct"})

      refute Visibility.visible_to?(post, bob.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp extract_post_ids(entries) do
    Enum.map(entries, fn
      %{type: :post, data: post} -> post.id
      %{type: :boost, data: boost} -> boost.post_id
      %Post{} = post -> post.id
    end)
  end
end

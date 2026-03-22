defmodule Hybridsocial.Feeds.AlgorithmTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Feeds.Algorithm
  alias Hybridsocial.Feeds.Signals
  alias Hybridsocial.Social.{Post, Follow, Reaction}

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

  defp create_post(identity, attrs) do
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

  defp create_follow(follower, followee) do
    %Follow{}
    |> Follow.changeset(%{
      follower_id: follower.id,
      followee_id: followee.id,
      status: :accepted
    })
    |> Repo.insert!()
  end

  describe "record_interaction/3" do
    test "creates a new interaction signal" do
      alice = create_user("algo_alice", "algo_alice@example.com")
      bob = create_user("algo_bob", "algo_bob@example.com")

      assert {:ok, signal} = Algorithm.record_interaction(alice.id, bob.id)
      assert signal.identity_id == alice.id
      assert signal.target_identity_id == bob.id
      assert signal.interaction_count == 1
    end

    test "increments existing interaction count" do
      alice = create_user("algo_inc_a", "algo_inc_a@example.com")
      bob = create_user("algo_inc_b", "algo_inc_b@example.com")

      {:ok, _} = Algorithm.record_interaction(alice.id, bob.id)
      {:ok, signal} = Algorithm.record_interaction(alice.id, bob.id)

      assert signal.interaction_count == 2
    end

    test "merges content tags" do
      alice = create_user("algo_tags_a", "algo_tags_a@example.com")
      bob = create_user("algo_tags_b", "algo_tags_b@example.com")

      {:ok, _} = Algorithm.record_interaction(alice.id, bob.id, ["elixir", "phoenix"])
      {:ok, signal} = Algorithm.record_interaction(alice.id, bob.id, ["elixir", "rust"])

      assert signal.content_tags["elixir"] == 2
      assert signal.content_tags["phoenix"] == 1
      assert signal.content_tags["rust"] == 1
    end
  end

  describe "algorithmic_timeline/2" do
    test "returns posts from followed accounts" do
      alice = create_user("algo_tl_a", "algo_tl_a@example.com")
      bob = create_user("algo_tl_b", "algo_tl_b@example.com")
      create_follow(alice, bob)

      post = create_post(bob, %{content: "Bob's algo post"})

      posts = Algorithm.algorithmic_timeline(alice.id)
      ids = Enum.map(posts, & &1.id)

      assert post.id in ids
    end

    test "includes popular public posts from non-followed accounts" do
      alice = create_user("algo_pop_a", "algo_pop_a@example.com")
      carol = create_user("algo_pop_c", "algo_pop_c@example.com")

      post = create_post(carol, %{content: "Popular post"})
      # Make it popular
      post |> Ecto.Changeset.change(reaction_count: 5) |> Repo.update!()

      posts = Algorithm.algorithmic_timeline(alice.id)
      ids = Enum.map(posts, & &1.id)

      assert post.id in ids
    end

    test "ranks posts by score (affinity-weighted)" do
      alice = create_user("algo_rank_a", "algo_rank_a@example.com")
      bob = create_user("algo_rank_b", "algo_rank_b@example.com")
      carol = create_user("algo_rank_c", "algo_rank_c@example.com")

      create_follow(alice, bob)
      create_follow(alice, carol)

      # Create strong affinity with Bob
      for _ <- 1..10 do
        Algorithm.record_interaction(alice.id, bob.id)
      end

      bob_post = create_post(bob, %{content: "Bob's ranked post"})
      carol_post = create_post(carol, %{content: "Carol's ranked post"})

      posts = Algorithm.algorithmic_timeline(alice.id)
      ids = Enum.map(posts, & &1.id)

      # Bob's post should rank higher due to affinity
      bob_idx = Enum.find_index(ids, &(&1 == bob_post.id))
      carol_idx = Enum.find_index(ids, &(&1 == carol_post.id))

      assert bob_idx != nil
      assert carol_idx != nil
      assert bob_idx < carol_idx
    end

    test "respects limit option" do
      alice = create_user("algo_lim_a", "algo_lim_a@example.com")
      bob = create_user("algo_lim_b", "algo_lim_b@example.com")
      create_follow(alice, bob)

      for i <- 1..5 do
        create_post(bob, %{content: "Post #{i}"})
      end

      posts = Algorithm.algorithmic_timeline(alice.id, limit: 3)
      assert length(posts) <= 3
    end
  end

  describe "precompute_signals/0" do
    test "creates signals from recent reactions" do
      alice = create_user("precomp_a", "precomp_a@example.com")
      bob = create_user("precomp_b", "precomp_b@example.com")

      post = create_post(bob, %{content: "React to me"})

      # Create a reaction
      %Reaction{}
      |> Reaction.changeset(%{post_id: post.id, identity_id: alice.id, type: "like"})
      |> Repo.insert!()

      assert :ok = Algorithm.precompute_signals()

      signal =
        Signals
        |> where([s], s.identity_id == ^alice.id and s.target_identity_id == ^bob.id)
        |> Repo.one()

      assert signal != nil
      assert signal.interaction_count >= 1
    end
  end
end

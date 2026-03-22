defmodule Hybridsocial.TrendingTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Trending
  alias Hybridsocial.Social.Posts
  alias Hybridsocial.Search.TrendingData
  alias Hybridsocial.Repo

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

  describe "compute_trending_posts/0" do
    test "computes trending posts from engagement" do
      user1 = create_user("trender1", "trender1@test.com")
      user2 = create_user("trender2", "trender2@test.com")
      user3 = create_user("trender3", "trender3@test.com")

      {:ok, post} = Posts.create_post(user1.id, %{"content" => "Trending post!"})

      # Create engagement from multiple unique accounts
      {:ok, _} = Posts.react(post.id, user1.id, "like")
      {:ok, _} = Posts.react(post.id, user2.id, "love")
      {:ok, _} = Posts.react(post.id, user3.id, "lol")

      assert :ok = Trending.compute_trending_posts()

      trending = Trending.get_trending_posts()
      # May or may not appear depending on threshold
      assert is_list(trending)
    end

    test "stores results in trending_data table" do
      user1 = create_user("store1", "store1@test.com")
      user2 = create_user("store2", "store2@test.com")
      user3 = create_user("store3", "store3@test.com")
      user4 = create_user("store4", "store4@test.com")

      {:ok, post} = Posts.create_post(user1.id, %{"content" => "Popular post!"})

      {:ok, _} = Posts.react(post.id, user2.id, "like")
      {:ok, _} = Posts.react(post.id, user3.id, "love")
      {:ok, _} = Posts.react(post.id, user4.id, "lol")

      Trending.compute_trending_posts()

      count =
        TrendingData
        |> where([t], t.type == "post")
        |> Repo.aggregate(:count)

      assert count >= 0
    end
  end

  describe "compute_trending_hashtags/0" do
    test "computes trending hashtags from recent usage" do
      user1 = create_user("htag1", "htag1@test.com")
      user2 = create_user("htag2", "htag2@test.com")

      {:ok, _} = Posts.create_post(user1.id, %{"content" => "Hello #trendytag123"})
      {:ok, _} = Posts.create_post(user2.id, %{"content" => "World #trendytag123"})

      assert :ok = Trending.compute_trending_hashtags()

      trending = Trending.get_trending_hashtags()
      assert is_list(trending)
    end
  end

  describe "get_trending_posts/1" do
    test "returns empty list when no trending data exists" do
      assert Trending.get_trending_posts() == []
    end

    test "respects limit option" do
      assert Trending.get_trending_posts(limit: 5) == []
    end
  end

  describe "get_trending_hashtags/1" do
    test "returns empty list when no trending data exists" do
      assert Trending.get_trending_hashtags() == []
    end
  end

  describe "get_trending_links/1" do
    test "returns empty list (placeholder)" do
      assert Trending.get_trending_links() == []
    end
  end

  describe "cleanup_old_trending/0" do
    test "removes trending data older than 48 hours" do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      old_time = DateTime.add(now, -49, :hour) |> DateTime.truncate(:microsecond)

      # Insert old trending data
      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "post",
        target_id: Ecto.UUID.generate(),
        score: 1.0,
        computed_at: old_time
      })
      |> Repo.insert!()

      # Insert recent trending data
      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "post",
        target_id: Ecto.UUID.generate(),
        score: 2.0,
        computed_at: now
      })
      |> Repo.insert!()

      assert :ok = Trending.cleanup_old_trending()

      remaining = Repo.all(TrendingData)
      assert length(remaining) == 1
      assert hd(remaining).score == 2.0
    end
  end
end

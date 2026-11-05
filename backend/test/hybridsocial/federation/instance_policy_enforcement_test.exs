defmodule Hybridsocial.Federation.InstancePolicyEnforcementTest do
  @moduledoc """
  Instance policies and account suspension must reach what people actually see,
  including posts stored before the policy was added.
  """
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Federation
  alias Hybridsocial.Feeds
  alias Hybridsocial.Feeds.Algorithms.Chronological
  alias Hybridsocial.Social
  alias Hybridsocial.Social.{Boost, Post, Posts}
  alias Hybridsocial.Trending

  setup do
    try do
      Hybridsocial.Cache.flush_pattern("feed:*")
    rescue
      _ -> :ok
    end

    :ok
  end

  defp make_remote(identity, url) do
    {1, _} =
      Repo.update_all(from(i in Identity, where: i.id == ^identity.id),
        set: [is_local: false, ap_actor_url: url]
      )

    Repo.get!(Identity, identity.id)
  end

  defp remote_user(handle, domain) do
    handle
    |> create_user()
    |> make_remote("https://#{domain}/users/#{handle}")
  end

  defp create_post(identity, content \\ "hello") do
    {:ok, post} = Posts.create_post(identity.id, %{"content" => content})
    post
  end

  defp global_ids, do: Feeds.global_timeline(viewer_id: nil) |> Enum.map(& &1.id)

  describe "suspending a domain" do
    test "hides posts stored before the policy, and lifting it restores them" do
      post = create_post(remote_user("evil_a", "evil.example"))
      assert post.id in global_ids()

      {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", "spam", nil)
      refute post.id in global_ids()

      {:ok, _} = Federation.delete_instance_policy("evil.example")
      assert post.id in global_ids()
    end

    test "leaves other domains alone" do
      post = create_post(remote_user("fine_a", "fine.example"))
      {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)

      assert post.id in global_ids()
    end

    test "matches an actor URL with a port" do
      author = "evil_port" |> create_user() |> make_remote("https://evil.example:8443/u/x")
      post = create_post(author)

      {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)
      refute post.id in global_ids()
    end

    test "does not hide imported local accounts that kept the old host in their URL" do
      imported = create_user("imported_a")

      {1, _} =
        Repo.update_all(from(i in Identity, where: i.id == ^imported.id),
          set: [ap_actor_url: "https://evil.example/users/imported_a"]
        )

      post = create_post(imported)
      {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)

      assert post.id in global_ids()
    end

    test "reaches the public, hashtag, trending and profile feeds" do
      author = remote_user("evil_b", "evil.example")
      post = create_post(author, "flood #floodtag")
      post |> Ecto.Changeset.change(reaction_count: 50) |> Repo.update!()

      {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)

      refute post.id in ids(Feeds.public_timeline(local_only: false, viewer_id: nil))
      refute post.id in ids(Feeds.hashtag_timeline("floodtag", viewer_id: nil))
      refute post.id in ids(Feeds.global_timeline(sort: "trending", viewer_id: nil))
      refute post.id in ids(Posts.posts_by_identity(author.id, viewer_id: nil))
    end

    test "hides the posts and boosts from followers' home feeds too" do
      viewer = create_user("home_viewer")
      author = remote_user("evil_c", "evil.example")
      booster = create_user("home_booster")
      {:ok, _} = Social.follow(viewer.id, booster.id)
      accept_follow(viewer, author)

      post = create_post(author)

      {:ok, _} =
        %Boost{}
        |> Ecto.Changeset.change(identity_id: booster.id, post_id: post.id)
        |> Repo.insert()

      assert post.id in home_post_ids(viewer)

      {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)
      refute post.id in home_post_ids(viewer)
    end
  end

  describe "silencing a domain" do
    test "hides stored posts from public timelines but not from followers" do
      viewer = create_user("silence_viewer")
      author = remote_user("loud_a", "loud.example")
      accept_follow(viewer, author)
      post = create_post(author)

      {:ok, _} = Federation.set_instance_policy("loud.example", "silence", nil, nil)

      refute post.id in global_ids()
      assert post.id in home_post_ids(viewer)
    end
  end

  describe "suspending an account" do
    test "hides their posts from timelines" do
      author = create_user("susp_a")
      post = create_post(author)

      {:ok, _} = Accounts.suspend_identity(author)
      refute post.id in global_ids()

      {:ok, _} = Accounts.unsuspend_identity(Repo.get!(Identity, author.id))
      assert post.id in global_ids()
    end
  end

  describe "trending" do
    defp trending_tags do
      Trending.get_trending_hashtags() |> Enum.map(& &1.target_id)
    end

    defp flood_tag(tag) do
      a = remote_user("#{tag}_a", "evil.example")
      b = remote_user("#{tag}_b", "evil.example")
      for author <- [a, b], do: create_post(author, "buy now ##{tag}")
      {a, b}
    end

    test "a suspended domain can't push a hashtag into trending" do
      flood_tag("floodone")
      :ok = Trending.compute_trending_hashtags()
      assert "floodone" in trending_tags()

      {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)
      :ok = Trending.compute_trending_hashtags()
      refute "floodone" in trending_tags()
    end

    test "suspended accounts no longer count towards a hashtag" do
      {a, b} = flood_tag("floodtwo")
      {:ok, _} = Accounts.suspend_identity(a)
      {:ok, _} = Accounts.suspend_identity(b)

      :ok = Trending.compute_trending_hashtags()
      refute "floodtwo" in trending_tags()
    end

    test "trending posts drop out at read time, before the next compute" do
      author = remote_user("trend_author", "evil.example")
      post = create_post(author)

      for handle <- ~w(trend_r1 trend_r2 trend_r3) do
        {:ok, _} = Posts.react(post.id, create_user(handle).id, "like")
      end

      :ok = Trending.compute_trending_posts()
      assert post.id in Enum.map(Trending.get_trending_posts(), & &1.post.id)

      {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)
      refute post.id in Enum.map(Trending.get_trending_posts(), & &1.post.id)
    end
  end

  describe "domain validation" do
    test "normalizes harmless variations to the bare host" do
      for input <- [
            "Evil.Example",
            "  evil.example ",
            "https://evil.example/",
            "http://EVIL.example"
          ] do
        assert {:ok, %{domain: "evil.example"}} =
                 Federation.set_instance_policy(input, "suspend", nil, nil)
      end

      assert [%{domain: "evil.example"}] = Federation.list_instance_policies()
    end

    test "rejects handles and profile URLs instead of widening them to the host" do
      for input <- [
            "@bob@evil.example",
            "bob@evil.example",
            "https://evil.example/users/bob",
            "evil",
            "not a domain"
          ] do
        assert {:error, changeset} = Federation.set_instance_policy(input, "suspend", nil, nil)
        assert %{domain: [_]} = errors_on(changeset)
      end

      assert Federation.list_instance_policies() == []
    end

    test "domain_allowed?/1 ignores the case of the sender's host" do
      {:ok, _} = Federation.set_instance_policy("evil.example", "suspend", nil, nil)
      refute Federation.domain_allowed?("EVIL.example")
    end
  end

  defp ids(posts), do: Enum.map(posts, & &1.id)

  defp accept_follow(follower, followee) do
    %Hybridsocial.Social.Follow{}
    |> Ecto.Changeset.change(
      follower_id: follower.id,
      followee_id: followee.id,
      status: :accepted
    )
    |> Repo.insert!()
  end

  defp home_post_ids(viewer) do
    Chronological.home_feed(viewer.id, [])
    |> Enum.map(fn
      %{data: %Post{id: id}} -> id
      %{data: %Boost{post_id: id}} -> id
    end)
  end
end

defmodule Hybridsocial.Feeds.Algorithms.TrendingTest do
  # Not async: the home-timeline test goes through the shared feed cache.
  use Hybridsocial.DataCase, async: false

  import Ecto.Query

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Feeds
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Posts
  alias Hybridsocial.Trending.ExploreFeed

  setup do
    try do
      Hybridsocial.Cache.flush_pattern("feed:*")
    rescue
      _ -> :ok
    end

    :ok
  end

  # A bare identity: hashing a password per fan adds minutes to the suite.
  defp user(handle) do
    id = Ecto.UUID.generate()
    handle = "#{handle}#{System.unique_integer([:positive])}"

    Repo.insert!(%Identity{
      id: id,
      type: "user",
      handle: handle,
      display_name: handle,
      ap_actor_url: "https://local.test/actors/#{id}",
      inbox_url: "https://local.test/actors/#{id}/inbox",
      outbox_url: "https://local.test/actors/#{id}/outbox",
      public_key: "test",
      private_key: "test"
    })
  end

  defp remote_user(handle) do
    identity = user(handle)

    from(i in Identity, where: i.id == ^identity.id)
    |> Repo.update_all(
      set: [is_local: false, ap_actor_url: "https://remote.example/users/#{identity.id}"]
    )

    Repo.get!(Identity, identity.id)
  end

  defp engaged_post(author, fans) do
    {:ok, post} = Posts.create_post(author.id, %{"content" => "post by #{author.handle}"})

    for _ <- 1..fans//1 do
      {:ok, _} = Posts.react(post.id, user("fan").id, "like")
    end

    post
  end

  defp explore_ids(opts), do: opts |> ExploreFeed.list() |> Enum.map(&elem(&1, 0).id)

  defp top(viewer, opts) do
    viewer.id
    |> Feeds.home_timeline(Keyword.put(opts, :algorithm, "trending"))
    |> Enum.map(& &1.id)
  end

  defp walk_top(viewer, opts, seen \\ [], guard \\ 50)
  defp walk_top(_viewer, _opts, _seen, 0), do: flunk("pagination did not terminate")

  defp walk_top(viewer, opts, seen, guard) do
    case top(viewer, opts) do
      [] ->
        seen

      page ->
        walk_top(viewer, Keyword.put(opts, :max_id, List.last(page)), seen ++ page, guard - 1)
    end
  end

  setup do
    viewer = user("viewer")
    # Uneven engagement, several posts per author: the old per-request ranking
    # re-sorted these by score and capped authors per page, so a walk repeated
    # and skipped posts.
    authors = for n <- 1..4, do: user("author#{n}")

    posts =
      for {author, i} <- Enum.with_index(authors), fans <- [1, 3, 2] do
        engaged_post(author, fans + i)
      end

    :ok = ExploreFeed.refresh()
    %{viewer: viewer, posts: posts}
  end

  describe "Home's Top tab" do
    test "is the precomputed Trending feed, in its order", %{viewer: viewer} do
      assert top(viewer, limit: 40) == explore_ids(viewer_id: viewer.id, limit: 40)
    end

    test "walking every page returns each post once, and all of them", %{viewer: viewer} do
      walked = walk_top(viewer, limit: 3)

      assert walked == Enum.uniq(walked)
      assert walked == explore_ids(viewer_id: viewer.id, limit: 40)
    end

    test "an unknown cursor ends the feed rather than restarting it", %{viewer: viewer} do
      assert top(viewer, max_id: Ecto.UUID.generate()) == []
    end

    test "a newer-than poll gets nothing", %{viewer: viewer, posts: [post | _]} do
      assert top(viewer, min_id: post.id) == []
      assert top(viewer, since_id: post.id) == []
    end

    test "isn't served Latest's cached first page", %{viewer: viewer} do
      # Latest caches the viewer's (empty: they follow nobody) home page.
      assert Feeds.home_timeline(viewer.id) == []
      refute top(viewer, []) == []
    end
  end

  describe "sort: \"trending\" on the public and global timelines" do
    test "local_only reads only this instance's half of the feed" do
      remote = engaged_post(remote_user("remote"), 4)
      :ok = ExploreFeed.refresh()

      local_ids =
        [sort: "trending", local_only: true, viewer_id: nil, limit: 40]
        |> Feeds.public_timeline()
        |> Enum.map(& &1.id)

      global_ids =
        [sort: "trending", viewer_id: nil, limit: 40]
        |> Feeds.global_timeline()
        |> Enum.map(& &1.id)

      assert local_ids == explore_ids(local_only: true, limit: 40)
      refute remote.id in local_ids
      assert remote.id in global_ids
    end
  end
end

defmodule Hybridsocial.Trending.ExploreFeedTest do
  use Hybridsocial.DataCase, async: true

  import Ecto.Query

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Repo
  alias Hybridsocial.Social
  alias Hybridsocial.Social.{Post, Posts}
  alias Hybridsocial.Trending
  alias Hybridsocial.Trending.{ExploreFeed, FeedEntry}

  # A bare identity: these tests never log in, and hashing a password per fan
  # adds minutes to the suite.
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

  defp remote_user(handle, domain \\ "remote.example") do
    identity = user(handle)

    from(i in Identity, where: i.id == ^identity.id)
    |> Repo.update_all(
      set: [is_local: false, ap_actor_url: "https://#{domain}/users/#{identity.id}"]
    )

    Repo.get!(Identity, identity.id)
  end

  defp post(author, content \\ "hello", attrs \\ %{}) do
    {:ok, post} = Posts.create_post(author.id, Map.merge(%{"content" => content}, attrs))
    post
  end

  defp engage(post, count) do
    for _ <- 1..count//1 do
      {:ok, _} = Posts.react(post.id, user("fan").id, "like")
    end

    post
  end

  defp remote_engaged_post(content \\ "remote post") do
    "author" |> remote_user() |> post(content) |> engage(3)
  end

  defp set_post(post, fields) do
    from(p in Post, where: p.id == ^post.id) |> Repo.update_all(set: fields)
    post
  end

  defp ids(opts \\ []), do: opts |> ExploreFeed.list() |> Enum.map(&elem(&1, 0).id)

  defp reason_of(post, opts \\ []) do
    opts
    |> ExploreFeed.list()
    |> Enum.find_value(fn {p, reason} -> if p.id == post.id, do: {:found, reason} end)
  end

  defp walk(opts, seen \\ [], guard \\ 50)
  defp walk(_opts, _seen, 0), do: flunk("pagination did not terminate")

  defp walk(opts, seen, guard) do
    case ids(opts) do
      [] -> seen
      page -> walk(Keyword.put(opts, :max_id, List.last(page)), seen ++ page, guard - 1)
    end
  end

  describe "sources" do
    test "blends local and remote posts" do
      local = "local" |> user() |> post() |> engage(1)
      remote = remote_engaged_post()

      assert :ok = ExploreFeed.refresh()

      assert local.id in ids()
      assert remote.id in ids()
    end

    test "a post of a trending tag is in the feed with the tag as its reason, even below the remote bar" do
      tagged = "author" |> remote_user() |> post("about #gardening") |> engage(1)
      "other" |> user() |> post("also #gardening")
      "third" |> user() |> post("more #gardening")
      :ok = Trending.compute_trending_hashtags()

      :ok = ExploreFeed.refresh()

      assert {:found, %{type: "tag", tag: "gardening"}} = reason_of(tagged)
    end

    test "a trending tag's post surfaces among the top, not just somewhere in the feed" do
      tagged = "author" |> remote_user() |> post("about #gardening") |> engage(1)
      "other" |> user() |> post("also #gardening")
      "third" |> user() |> post("more #gardening")
      for n <- 1..8, do: "r#{n}" |> remote_user() |> post() |> engage(3)
      :ok = Trending.compute_trending_hashtags()

      :ok = ExploreFeed.refresh()

      assert hd(ids(limit: 3) -- ids(local_only: true)) == tagged.id
    end

    test "a tag-stuffed post gets no way in through its tags" do
      stuffing = Enum.map_join(1..9, " ", &"#stuffed#{&1}")
      stuffed = "author" |> remote_user() |> post("#gardening #{stuffing}") |> engage(1)
      "other" |> user() |> post("also #gardening")
      "third" |> user() |> post("more #gardening")
      :ok = Trending.compute_trending_hashtags()

      :ok = ExploreFeed.refresh()

      refute stuffed.id in ids()
    end

    test "a private post does not make a tag trend" do
      for handle <- ["one", "two", "three"] do
        handle |> user() |> post("secret #hushhush", %{"visibility" => "followers"})
      end

      :ok = Trending.compute_trending_hashtags()

      assert Trending.get_trending_hashtags() |> Enum.map(& &1.target_id) == []
    end

    test "an account's best post comes in below the bar, labelled, but not if undiscoverable" do
      discoverable = remote_user("hot")
      best = discoverable |> post("best") |> engage(2)
      discoverable |> post("second") |> engage(1)

      hidden = remote_user("hidden")

      from(i in Identity, where: i.id == ^hidden.id)
      |> Repo.update_all(set: [discoverable: false])

      undiscoverable = hidden |> post("best") |> engage(2)
      hidden |> post("second") |> engage(1)

      :ok = ExploreFeed.refresh()

      assert {:found, %{type: "account"}} = reason_of(best)
      refute undiscoverable.id in ids()
    end

    test "a post that clears the bar on its own needs no label" do
      remote = remote_engaged_post()
      :ok = ExploreFeed.refresh()
      assert {:found, nil} = reason_of(remote)
    end

    test "a quiet instance's local share is kept up by recent unengaged local posts" do
      quiet = "quiet" |> user() |> post()
      unengaged_remote = "far" |> remote_user() |> post()

      :ok = ExploreFeed.refresh()

      assert quiet.id in ids()
      refute unengaged_remote.id in ids()
    end
  end

  describe "ranking" do
    test "engagement counts other accounts only, so self-engagement can't clear the bar" do
      author = remote_user("selfie")
      selfie = post(author)
      {:ok, _} = Posts.react(selfie.id, author.id, "like")
      {:ok, _} = Posts.boost(selfie.id, author.id)
      engage(selfie, 2)

      :ok = ExploreFeed.refresh()

      refute selfie.id in ids()
    end

    test "one account reacting and boosting counts as one account" do
      post = "author" |> remote_user() |> post()
      fan = user("fan")
      {:ok, _} = Posts.react(post.id, fan.id, "like")
      {:ok, _} = Posts.boost(post.id, fan.id)
      engage(post, 1)

      :ok = ExploreFeed.refresh()

      refute post.id in ids()
    end

    test "a moderated account's engagement stops counting" do
      post = remote_engaged_post()
      {:ok, _} = Posts.react(post.id, user("fan").id, "like")
      :ok = ExploreFeed.refresh()
      assert post.id in ids()

      fans =
        from(r in Hybridsocial.Social.Reaction,
          where: r.post_id == ^post.id,
          select: r.identity_id
        )
        |> Repo.all()

      from(i in Identity, where: i.id in ^fans) |> Repo.update_all(set: [is_shadow_banned: true])
      :ok = ExploreFeed.refresh()

      refute post.id in ids()
    end

    test "engagers past the per-domain cap don't count" do
      piled_on = "piled" |> remote_user() |> post("one server")
      broad = "broad" |> remote_user() |> post("many servers")

      for n <- 1..12 do
        {:ok, _} = Posts.react(piled_on.id, remote_user("a#{n}", "farm.example").id, "like")
        {:ok, _} = Posts.react(broad.id, remote_user("b#{n}", "s#{n}.example").id, "like")
      end

      set_post(piled_on, published_at: Repo.get!(Post, broad.id).published_at)
      :ok = ExploreFeed.refresh()

      scores = Repo.all(from e in FeedEntry, select: {e.post_id, e.score}) |> Map.new()

      assert scores[broad.id] > scores[piled_on.id]
    end

    test "a future-dated post is left out rather than ranked as maximally fresh" do
      future = remote_engaged_post()
      set_post(future, published_at: DateTime.add(DateTime.utc_now(), 7, :day))

      :ok = ExploreFeed.refresh()

      refute future.id in ids()
    end

    test "a backfilled post older than the window is left out" do
      old = remote_engaged_post()
      set_post(old, published_at: DateTime.add(DateTime.utc_now(), -30, :day))

      :ok = ExploreFeed.refresh()

      refute old.id in ids()
    end

    test "an author's further posts are penalized, so one account can't fill the top" do
      prolific = remote_user("prolific")
      flood = for n <- 1..4, do: prolific |> post("flood #{n}") |> engage(4)
      others = for n <- 1..4, do: "other#{n}" |> remote_user() |> post() |> engage(3)

      :ok = ExploreFeed.refresh()

      top_four = ids(limit: 4)
      assert length(Enum.filter(top_four, &(&1 in Enum.map(flood, fn p -> p.id end)))) == 1
      assert length(Enum.filter(top_four, &(&1 in Enum.map(others, fn p -> p.id end)))) == 3
    end

    test "the order doesn't change just because time passed" do
      for n <- 1..3, do: "a#{n}" |> remote_user() |> post() |> engage(n + 2)
      for n <- 1..2, do: "l#{n}" |> user() |> post() |> engage(n)

      :ok = ExploreFeed.refresh()
      before = ids()

      :ok = ExploreFeed.refresh(DateTime.add(DateTime.utc_now(), 3, :hour))

      assert ids() == before
    end
  end

  describe "local and remote share" do
    test "local posts keep their share however engaged remote posts are" do
      for n <- 1..6, do: "r#{n}" |> remote_user() |> post() |> engage(5)
      locals = for n <- 1..2, do: "l#{n}" |> user() |> post() |> engage(1)

      :ok = ExploreFeed.refresh()

      positions =
        for %{id: id} <- locals, do: Enum.find_index(ids(), &(&1 == id))

      # About one in four: slots can tie, so a post may land one place earlier.
      assert Enum.sort(positions) in [[1, 5], [1, 6], [2, 5], [2, 6]]
    end

    test "the feed backfills when either side is empty" do
      remote_only = for n <- 1..3, do: "r#{n}" |> remote_user() |> post() |> engage(3)
      :ok = ExploreFeed.refresh()
      assert length(ids()) == length(remote_only)

      from(p in Post) |> Repo.update_all(set: [deleted_at: DateTime.utc_now()])

      local_only = for n <- 1..3, do: "l#{n}" |> user() |> post() |> engage(1)
      :ok = ExploreFeed.refresh()
      assert length(ids()) == length(local_only)
    end
  end

  describe "pagination" do
    setup do
      prolific = remote_user("prolific")
      for n <- 1..6, do: prolific |> post("flood #{n}") |> engage(rem(n, 3) + 3)
      for n <- 1..12, do: "r#{n}" |> remote_user() |> post() |> engage(rem(n, 4) + 3)
      for n <- 1..5, do: "l#{n}" |> user() |> post() |> engage(rem(n, 2) + 1)
      :ok = ExploreFeed.refresh()
      :ok
    end

    test "walking every page returns each entry exactly once, in order" do
      all = ids(limit: 40)
      assert length(all) == 23

      walked = walk(limit: 4)

      assert walked == all
      assert walked == Enum.uniq(walked)
    end

    test "pages stay full when the viewer's blocks and mutes remove entries" do
      viewer = user("viewer")
      all = ids(limit: 40)
      blocked = Repo.get!(Post, Enum.at(all, 0)).identity_id
      {:ok, _} = Social.block(viewer.id, blocked)

      page = ids(limit: 4, viewer_id: viewer.id)

      assert length(page) == 4
      refute Enum.at(all, 0) in page
    end

    test "a cursor retired by a refresh still pages on rather than restarting" do
      [_ | _] = first_page = ids(limit: 4)
      cursor = List.last(first_page)

      # The boundary post drops out of the feed entirely.
      set_post(%{id: cursor}, deleted_at: DateTime.utc_now())
      :ok = ExploreFeed.refresh()

      next = ids(limit: 4, max_id: cursor)

      assert next != []
      assert Enum.at(ids(limit: 1), 0) not in next
    end

    test "an unknown or malformed cursor returns nothing rather than page one" do
      assert ids(max_id: Ecto.UUID.generate()) == []
      assert ids(max_id: "not-a-uuid") == []
    end
  end

  describe "moderation, applied on read" do
    setup do
      post = remote_engaged_post()
      :ok = ExploreFeed.refresh()
      assert post.id in ids()
      %{post: post}
    end

    test "a post hidden after the refresh is gone at once", %{post: post} do
      set_post(post, hidden_at: DateTime.utc_now())
      refute post.id in ids()
    end

    test "a post deleted after the refresh is gone at once", %{post: post} do
      set_post(post, deleted_at: DateTime.utc_now())
      refute post.id in ids()
    end

    test "a suspended author's post is gone at once", %{post: post} do
      from(i in Identity, where: i.id == ^post.identity_id)
      |> Repo.update_all(set: [is_suspended: true])

      refute post.id in ids()
    end

    test "a silenced author's post is gone at once", %{post: post} do
      from(i in Identity, where: i.id == ^post.identity_id)
      |> Repo.update_all(set: [is_silenced: true])

      refute post.id in ids()
    end

    test "a shadow-banned author's post is gone at once", %{post: post} do
      from(i in Identity, where: i.id == ^post.identity_id)
      |> Repo.update_all(set: [is_shadow_banned: true])

      refute post.id in ids()
    end

    test "a viewer's block applies in both directions", %{post: post} do
      viewer = user("viewer")
      assert post.id in ids(viewer_id: viewer.id)

      {:ok, _} = Social.block(post.identity_id, viewer.id)

      refute post.id in ids(viewer_id: viewer.id)
    end

    test "a viewer's domain block applies", %{post: post} do
      viewer = user("viewer")

      Repo.insert_all("user_domain_blocks", [
        %{
          id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          identity_id: Ecto.UUID.dump!(viewer.id),
          domain: "remote.example",
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ])

      refute post.id in ids(viewer_id: viewer.id)
      assert post.id in ids()
    end

    test "sensitive posts are left out for anonymous viewers only", %{post: post} do
      set_post(post, sensitive: true)

      refute post.id in ids()
      assert post.id in ids(viewer_id: user("viewer").id)
    end

    test "a post quoting something unfit to be public is left out", %{post: post} do
      quoted = "quoted" |> user() |> post()
      set_post(post, quote_id: quoted.id)
      assert post.id in ids()

      set_post(quoted, hidden_at: DateTime.utc_now())
      refute post.id in ids()
    end

    test "local_only returns only this instance's posts", %{post: post} do
      local = "local" |> user() |> post() |> engage(1)
      :ok = ExploreFeed.refresh()

      assert local.id in ids(local_only: true)
      refute post.id in ids(local_only: true)
    end
  end

  describe "ineligible posts" do
    test "replies and orphan federated replies are not candidates" do
      parent = remote_engaged_post()

      {:ok, reply} =
        Posts.create_post(user("replier").id, %{"content" => "reply", "parent_id" => parent.id})

      engage(reply, 3)

      orphan = remote_engaged_post("orphan")
      set_post(orphan, parent_ap_id: "https://elsewhere.example/notes/1")

      :ok = ExploreFeed.refresh()

      refute reply.id in ids()
      refute orphan.id in ids()
    end

    test "a refresh replaces the previous feed" do
      post = remote_engaged_post()
      :ok = ExploreFeed.refresh()
      assert post.id in ids()

      set_post(post, deleted_at: DateTime.utc_now())
      :ok = ExploreFeed.refresh()

      assert Repo.get!(FeedEntry, post.id).active == false
    end
  end

  describe "followed_author_ids/2" do
    test "covers followed authors and the viewer, not strangers" do
      viewer = user("viewer")
      followed = user("followed")
      stranger = user("stranger")
      {:ok, _} = Social.follow(viewer.id, followed.id)

      result =
        ExploreFeed.followed_author_ids(viewer.id, [viewer.id, followed.id, stranger.id])

      assert MapSet.member?(result, viewer.id)
      assert MapSet.member?(result, followed.id)
      refute MapSet.member?(result, stranger.id)
    end
  end
end

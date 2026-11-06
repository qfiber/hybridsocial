defmodule HybridsocialWeb.Api.V1.AnonymousLockedRoutesTest do
  use HybridsocialWeb.ConnCase, async: false

  alias Hybridsocial.Feeds
  alias Hybridsocial.Repo
  alias Hybridsocial.Social
  alias Hybridsocial.Social.Posts
  alias Hybridsocial.Trending
  alias HybridsocialWeb.Api.V1.StreamingController

  setup do
    try do
      Hybridsocial.Cache.flush_pattern("feed:*")
    rescue
      _ -> :ok
    end

    tag = "lockedtag#{System.unique_integer([:positive])}"
    locked = user("locked") |> Ecto.Changeset.change(is_locked: true) |> Repo.update!()
    open = user("open")

    {:ok, locked_post} = Posts.create_post(locked.id, %{"content" => "lockedword ##{tag}"})
    {:ok, open_post} = Posts.create_post(open.id, %{"content" => "openword ##{tag}"})

    %{tag: tag, locked: locked, open: open, locked_post: locked_post, open_post: open_post}
  end

  defp user(handle), do: create_user("#{handle}#{System.unique_integer([:positive])}")
  defp member(conn), do: auth_conn(conn, user("member"))

  defp ids(body) when is_list(body), do: Enum.map(body, & &1["id"])

  # Each route must leave out a locked account's post for anonymous viewers, keep
  # the other post, and still show both to logged-in members.
  defp assert_only_members_see_locked(conn, path, ctx) do
    anonymous = conn |> get(path) |> json_response(200) |> ids()
    assert ctx.open_post.id in anonymous, "#{path}: anonymous should still see open posts"
    refute ctx.locked_post.id in anonymous, "#{path}: anonymous saw a locked account's post"

    logged_in = conn |> member() |> get(path) |> json_response(200) |> ids()
    assert ctx.locked_post.id in logged_in, "#{path}: a member lost a locked account's post"
    assert ctx.open_post.id in logged_in
  end

  test "the local timeline", %{conn: conn} = ctx do
    assert_only_members_see_locked(conn, "/api/v1/timelines/public", ctx)
  end

  test "the global timeline", %{conn: conn} = ctx do
    assert_only_members_see_locked(conn, "/api/v1/timelines/global", ctx)
  end

  test "a hashtag timeline", %{conn: conn, tag: tag} = ctx do
    assert_only_members_see_locked(conn, "/api/v1/timelines/tag/#{tag}", ctx)
  end

  test "ranked orders of the timelines", %{conn: conn} = ctx do
    for post <- [ctx.locked_post, ctx.open_post] do
      {:ok, _} = Posts.react(post.id, user("fan").id, "like")
    end

    assert_only_members_see_locked(conn, "/api/v1/timelines/public?sort=trending", ctx)
    assert_only_members_see_locked(conn, "/api/v1/timelines/global?sort=trending", ctx)
  end

  test "an anonymous request can't poison a member's cached first page", %{conn: conn} = ctx do
    assert ctx.open_post.id in (conn
                                |> get("/api/v1/timelines/public")
                                |> json_response(200)
                                |> ids())

    assert ctx.locked_post.id in (conn
                                  |> member()
                                  |> get("/api/v1/timelines/public")
                                  |> json_response(200)
                                  |> ids())

    refute ctx.locked_post.id in (conn
                                  |> get("/api/v1/timelines/public")
                                  |> json_response(200)
                                  |> ids())
  end

  test "the shared snapshot stays complete for members", ctx do
    shared = Feeds.global_timeline(viewer_id: nil, include_locked: true) |> Enum.map(& &1.id)
    anonymous = Feeds.global_timeline(viewer_id: nil) |> Enum.map(& &1.id)

    assert ctx.locked_post.id in shared
    refute ctx.locked_post.id in anonymous
  end

  test "trending posts", %{conn: conn} = ctx do
    for post <- [ctx.locked_post, ctx.open_post], n <- 1..3 do
      {:ok, _} = Posts.react(post.id, user("fan#{n}").id, "like")
    end

    :ok = Trending.compute_trending_posts()

    anonymous = conn |> get("/api/v1/trends/statuses") |> json_response(200) |> inspect()
    assert anonymous =~ ctx.open_post.id
    refute anonymous =~ ctx.locked_post.id

    logged_in =
      conn |> member() |> get("/api/v1/trends/statuses") |> json_response(200) |> inspect()

    assert logged_in =~ ctx.locked_post.id
  end

  test "trending accounts", %{conn: conn} = ctx do
    anonymous = conn |> get("/api/v1/trends/accounts") |> json_response(200) |> ids()
    refute ctx.locked.id in anonymous

    logged_in = conn |> member() |> get("/api/v1/trends/accounts") |> json_response(200) |> ids()
    assert ctx.locked.id in logged_in
  end

  test "locked accounts' posts don't count toward trending tags", ctx do
    {:ok, _} = Posts.create_post(user("two").id, %{"content" => "more ##{ctx.tag}"})
    :ok = Trending.compute_trending_hashtags()

    assert [%{metadata: metadata}] = Trending.get_trending_hashtags()
    assert metadata["post_count"] == 2
    assert metadata["unique_accounts"] == 2
    assert Enum.sum(metadata["history"]) == 2
  end

  test "the new members directory", %{conn: conn} = ctx do
    anonymous = conn |> get("/api/v1/directory/new?limit=50") |> json_response(200) |> ids()
    refute ctx.locked.id in anonymous

    logged_in =
      conn |> member() |> get("/api/v1/directory/new?limit=50") |> json_response(200) |> ids()

    assert ctx.locked.id in logged_in
  end

  test "search, for accounts and posts", %{conn: conn} = ctx do
    anonymous = conn |> get("/api/v1/search", %{"q" => ctx.locked.handle}) |> json_response(200)
    refute ctx.locked.id in ids(anonymous["accounts"])

    logged_in =
      conn |> member() |> get("/api/v1/search", %{"q" => ctx.locked.handle}) |> json_response(200)

    assert ctx.locked.id in ids(logged_in["accounts"])

    posts = conn |> get("/api/v1/search", %{"q" => "lockedword"}) |> json_response(200)
    refute ctx.locked_post.id in ids(posts["posts"])
    refute ctx.locked_post.id in ids(posts["statuses"])
  end

  test "someone else's follower and following lists", %{conn: conn} = ctx do
    {:ok, _} = Social.follow(ctx.locked.id, ctx.open.id)
    {:ok, _} = Social.follow(ctx.open.id, ctx.locked.id)

    for path <- ["followers", "following"] do
      url = "/api/v1/accounts/#{ctx.open.id}/#{path}"
      refute ctx.locked.id in (conn |> get(url) |> json_response(200) |> ids())
    end

    url = "/api/v1/accounts/#{ctx.open.id}/followers"
    assert ctx.locked.id in (conn |> member() |> get(url) |> json_response(200) |> ids())
  end

  test "a boost of a locked account's post on someone's timeline", ctx do
    {:ok, _} = Posts.boost(ctx.locked_post.id, ctx.open.id)

    boosted = fn viewer_id ->
      ctx.open.id
      |> Feeds.account_timeline(viewer_id, [])
      |> Enum.filter(&(&1.type == :boost))
      |> Enum.map(& &1.data.post_id)
    end

    refute ctx.locked_post.id in boosted.(nil)
    assert ctx.locked_post.id in boosted.(user("member").id)
  end

  describe "public live streams" do
    test "a locked account's post isn't sent to anonymous viewers", ctx do
      refute StreamingController.deliver_to_viewer?(%{account: %{id: ctx.locked.id}}, nil)
      refute StreamingController.deliver_to_viewer?(%{"account" => %{"id" => ctx.locked.id}}, nil)
    end

    test "other posts and events are", ctx do
      assert StreamingController.deliver_to_viewer?(%{account: %{id: ctx.open.id}}, nil)
      assert StreamingController.deliver_to_viewer?(ctx.locked_post.id, nil)
    end

    test "members get everything", ctx do
      assert StreamingController.deliver_to_viewer?(%{account: %{id: ctx.locked.id}}, ctx.open.id)
    end
  end
end

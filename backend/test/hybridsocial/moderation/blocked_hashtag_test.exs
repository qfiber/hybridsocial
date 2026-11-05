defmodule Hybridsocial.Moderation.BlockedHashtagTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Config
  alias Hybridsocial.Federation.Inbox
  alias Hybridsocial.Feeds
  alias Hybridsocial.Feeds.Algorithms.Chronological
  alias Hybridsocial.Moderation
  alias Hybridsocial.Search.Backends.PostgresqlBackend
  alias Hybridsocial.Social.{Follow, Post, Posts}
  alias Hybridsocial.Streaming
  alias Hybridsocial.Trending

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)

    try do
      Hybridsocial.Cache.flush_pattern("feed:*")
    rescue
      _ -> :ok
    end

    :ok
  end

  defp block(name, action) do
    {:ok, block} = Moderation.block_hashtag(%{"name" => name, "action" => action})
    block
  end

  defp post_by(handle, content) do
    {:ok, post} = Posts.create_post(create_user(handle).id, %{"content" => content})
    post
  end

  defp global_ids, do: Feeds.global_timeline(viewer_id: nil) |> Enum.map(& &1.id)
  defp tag_ids(tag), do: Feeds.hashtag_timeline(tag, viewer_id: nil) |> Enum.map(& &1.id)
  defp trending_tags, do: Trending.get_trending_hashtags() |> Enum.map(& &1.target_id)

  defp trend(tag) do
    post_by("#{tag}_a", "hello ##{tag}")
    post_by("#{tag}_b", "hello ##{tag}")
    :ok = Trending.compute_trending_hashtags()
    assert tag in trending_tags()
  end

  describe "no_trending" do
    test "drops the tag from trending immediately, and unblocking restores it" do
      trend("spamone")
      block = block("spamone", "no_trending")
      refute "spamone" in trending_tags()

      {:ok, _} = Moderation.unblock_hashtag(block.id)
      assert "spamone" in trending_tags()
    end

    test "leaves the posts and the tag page alone" do
      post = post_by("nt_author", "hello #spamtwo")
      block("spamtwo", "no_trending")

      assert post.id in global_ids()
      assert post.id in tag_ids("spamtwo")
    end
  end

  describe "hide" do
    test "removes posts from public timelines and the tag page" do
      post = post_by("hide_author", "hello #SpamThree")
      block("spamthree", "hide")

      refute post.id in global_ids()
      refute post.id in Enum.map(Feeds.public_timeline(viewer_id: nil), & &1.id)
      assert tag_ids("spamthree") == []
      assert tag_ids("SPAMTHREE") == []
    end

    test "a post with a longer tag isn't caught by a shorter blocked one" do
      post = post_by("prefix_author", "hello #spamfourteen")
      block("spamfour", "hide")

      assert post.id in global_ids()
    end

    test "followers still see the post at home" do
      viewer = create_user("hide_viewer")
      author = create_user("hide_followed")

      %Follow{}
      |> Ecto.Changeset.change(
        follower_id: viewer.id,
        followee_id: author.id,
        status: :accepted
      )
      |> Repo.insert!()

      {:ok, post} = Posts.create_post(author.id, %{"content" => "hello #spamfive"})
      block("spamfive", "hide")

      ids =
        Chronological.home_feed(viewer.id, [])
        |> Enum.map(fn %{data: %Post{id: id}} -> id end)

      assert post.id in ids
    end

    test "drops the post and the tag from search" do
      post = post_by("search_author", "findable #spamsix")
      block("spamsix", "hide")

      {:ok, posts} = PostgresqlBackend.search_posts("findable", nil, [])
      refute post.id in Enum.map(posts, & &1.id)

      {:ok, tags} = PostgresqlBackend.search_hashtags("spamsix", [])
      assert tags == []
    end

    test "keeps new posts off the public stream but not the author's own" do
      author = create_user("stream_author")
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "timeline:public")
      Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "user:#{author.id}")
      block("spamseven", "hide")

      Streaming.broadcast_post(%{
        visibility: "public",
        identity_id: author.id,
        tags: [%{name: "SpamSeven"}]
      })

      assert_receive %{event: "update"}
      refute_receive %{event: "update"}, 50

      Streaming.broadcast_post(%{visibility: "public", identity_id: author.id, tags: ["fine"]})
      assert_receive %{event: "update"}
      assert_receive %{event: "update"}
    end
  end

  describe "reject" do
    defp create_activity(object_overrides) do
      id = :erlang.unique_integer([:positive])

      %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "https://remote.example/activities/#{id}",
        "type" => "Create",
        "actor" => "https://remote.example/u/alice",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"],
        "object" =>
          Map.merge(
            %{
              "id" => "https://remote.example/objects/#{id}",
              "type" => "Note",
              "content" => "hello",
              "attributedTo" => "https://remote.example/u/alice",
              "published" => "2026-04-13T12:00:00Z",
              "to" => ["https://www.w3.org/ns/activitystreams#Public"]
            },
            object_overrides
          )
      }
    end

    test "refuses a remote post tagged through the AP tag array" do
      :ok = Config.set("mrf_policies", [])
      block("spameight", "reject")

      activity =
        create_activity(%{
          "tag" => [%{"type" => "Hashtag", "name" => "#SpamEight"}],
          "content" => ~s(<a href="https://x/tags/spameight">#<span>SpamEight</span></a>)
        })

      assert {:error, {:mrf_rejected, reason}} = Inbox.process(activity)
      assert reason =~ "spameight"
    end

    test "refuses a remote post that only inlines the tag" do
      block("spamnine", "reject")

      assert {:error, {:mrf_rejected, _}} =
               Inbox.process(create_activity(%{"content" => "hello #spamnine"}))
    end

    test "other actions don't refuse remote posts" do
      block("spamten", "hide")
      assert {:ok, _} = Inbox.process(create_activity(%{"content" => "hello #spamten"}))
    end

    test "also hides existing posts" do
      post = post_by("reject_author", "hello #spameleven")
      block("spameleven", "reject")

      refute post.id in global_ids()
    end
  end

  describe "block_hashtag/1" do
    test "normalizes the name and re-blocking updates the existing row" do
      first = block(" #Spam ", "no_trending")
      second = block("spam", "hide")

      assert first.name == "spam"
      assert second.action == "hide"
      assert [%{id: id, action: "hide"}] = Moderation.list_blocked_hashtags()
      assert id == first.id
    end

    test "accepts non-Latin tags" do
      assert %{name: "مرحبا"} = block("#مرحبا", "hide")
    end

    test "rejects anything that isn't a single valid tag" do
      for name <- ["two words", "#", "123", "a,b", ""] do
        assert {:error, changeset} =
                 Moderation.block_hashtag(%{"name" => name, "action" => "hide"})

        assert %{name: [_]} = errors_on(changeset)
      end
    end

    test "rejects an unknown action" do
      assert {:error, changeset} = Moderation.block_hashtag(%{"name" => "x", "action" => "nope"})
      assert %{action: [_]} = errors_on(changeset)
    end
  end
end

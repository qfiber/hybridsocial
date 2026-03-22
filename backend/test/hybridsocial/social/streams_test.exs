defmodule Hybridsocial.Social.StreamsTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Social.Streams
  alias Hybridsocial.Social.{Post, StreamView}

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
      post_type: "video_stream"
    }

    %Post{}
    |> Post.create_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "record_view/3" do
    test "records a view for a logged-in user" do
      alice = create_user("stream_alice", "stream_alice@example.com")
      post = create_post(alice)

      attrs = %{
        "watch_duration" => 30.0,
        "total_duration" => 60.0,
        "completed" => false,
        "replayed" => false,
        "source" => "feed"
      }

      assert {:ok, view} = Streams.record_view(post.id, alice.id, attrs)
      assert view.post_id == post.id
      assert view.identity_id == alice.id
      assert view.watch_duration == 30.0
      assert view.total_duration == 60.0
      assert view.completed == false
      assert view.source == "feed"
    end

    test "records a view for anonymous user" do
      alice = create_user("stream_anon", "stream_anon@example.com")
      post = create_post(alice)

      attrs = %{
        "watch_duration" => 10.0,
        "total_duration" => 60.0
      }

      assert {:ok, view} = Streams.record_view(post.id, nil, attrs)
      assert view.post_id == post.id
      assert is_nil(view.identity_id)
    end

    test "rejects invalid view data" do
      alice = create_user("stream_invalid", "stream_invalid@example.com")
      post = create_post(alice)

      attrs = %{"watch_duration" => -1.0, "total_duration" => 0.0}
      assert {:error, _changeset} = Streams.record_view(post.id, nil, attrs)
    end
  end

  describe "get_view_stats/1" do
    test "returns zero stats for no views" do
      alice = create_user("stats_zero", "stats_zero@example.com")
      post = create_post(alice)

      stats = Streams.get_view_stats(post.id)
      assert stats.total_views == 0
      assert stats.unique_viewers == 0
      assert stats.avg_watch_duration == 0.0
      assert stats.completion_rate == 0.0
      assert stats.replay_rate == 0.0
    end

    test "returns correct stats with views" do
      alice = create_user("stats_views", "stats_views@example.com")
      bob = create_user("stats_bob", "stats_bob@example.com")
      post = create_post(alice)

      # Bob watches partially
      Repo.insert!(%StreamView{
        post_id: post.id,
        identity_id: bob.id,
        watch_duration: 30.0,
        total_duration: 60.0,
        completed: false,
        replayed: false,
        source: "feed"
      })

      # Bob watches again and completes
      Repo.insert!(%StreamView{
        post_id: post.id,
        identity_id: bob.id,
        watch_duration: 60.0,
        total_duration: 60.0,
        completed: true,
        replayed: true,
        source: "feed"
      })

      stats = Streams.get_view_stats(post.id)
      assert stats.total_views == 2
      assert stats.unique_viewers == 1
      assert stats.avg_watch_duration == 45.0
      assert stats.completion_rate == 50.0
      assert stats.replay_rate == 50.0
    end
  end

  describe "streams_feed/2" do
    test "returns only video_stream posts" do
      alice = create_user("sfeed_alice", "sfeed_alice@example.com")
      video = create_post(alice, %{post_type: "video_stream", content: "My reel"})
      _text = create_post(alice, %{post_type: "text", content: "My text"})

      posts = Streams.streams_feed(nil)
      ids = Enum.map(posts, & &1.id)

      assert video.id in ids
      refute Enum.any?(ids, fn id -> id == _text.id end)
    end

    test "returns only public posts" do
      alice = create_user("sfeed_pub", "sfeed_pub@example.com")
      _private = create_post(alice, %{visibility: "followers", content: "Private reel"})

      posts = Streams.streams_feed(nil)
      assert posts == []
    end

    test "excludes deleted posts" do
      alice = create_user("sfeed_del", "sfeed_del@example.com")
      post = create_post(alice, %{content: "Deleted reel"})

      post |> Post.soft_delete_changeset() |> Repo.update!()

      posts = Streams.streams_feed(nil)
      ids = Enum.map(posts, & &1.id)
      refute post.id in ids
    end

    test "supports pagination with limit" do
      alice = create_user("sfeed_lim", "sfeed_lim@example.com")

      for i <- 1..5 do
        create_post(alice, %{content: "Reel #{i}"})
      end

      posts = Streams.streams_feed(nil, limit: 3)
      assert length(posts) == 3
    end
  end
end

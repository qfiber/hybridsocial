defmodule Hybridsocial.Social.StreamsTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.Streams
  alias Hybridsocial.Social.{Post, StreamView}
  alias Hybridsocial.Media.MediaFile

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

  # Attach a qualifying video to a post so it can appear in the streams
  # feed (which requires a non-deleted video >= min_duration). Defaults are
  # a 30s portrait clip (720x1280); pass :duration/:width/:height to
  # exercise the duration and orientation filters.
  defp attach_video(post, identity, opts \\ []) do
    Repo.insert!(%MediaFile{
      identity_id: identity.id,
      post_id: post.id,
      content_type: "video/mp4",
      file_size: 1_000,
      storage_path: "test/#{post.id}.mp4",
      duration: Keyword.get(opts, :duration, 30.0),
      width: Keyword.get(opts, :width, 720),
      height: Keyword.get(opts, :height, 1280)
    })

    post
  end

  # Flip an already-created author to a federated (remote) identity so we
  # can assert the streams feed's local-only filter.
  defp make_remote(identity) do
    {1, _} =
      Repo.update_all(from(i in Identity, where: i.id == ^identity.id), set: [is_local: false])

    identity
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

    test "accepts the source value the Streams player actually sends" do
      alice = create_user("stream_sources", "stream_sources@example.com")
      post = create_post(alice)
      base = %{"watch_duration" => 5.0, "total_duration" => 30.0}

      assert {:ok, view} =
               Streams.record_view(post.id, alice.id, Map.put(base, "source", "streams_feed"))

      assert view.source == "streams_feed"
    end

    test "rejects an unknown source" do
      alice = create_user("stream_badsource", "stream_badsource@example.com")
      post = create_post(alice)

      attrs = %{"watch_duration" => 5.0, "total_duration" => 30.0, "source" => "bogus"}
      assert {:error, changeset} = Streams.record_view(post.id, nil, attrs)
      assert %{source: ["is invalid"]} = errors_on(changeset)
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
    test "includes any local public post with a qualifying video, regardless of post_type" do
      alice = create_user("sfeed_alice", "sfeed_alice@example.com")

      clip =
        create_post(alice, %{post_type: "video_stream", content: "My clip"})
        |> attach_video(alice)

      # A non-video_stream local post that just happens to carry a
      # qualifying video still belongs — membership is by "has a video",
      # not post_type.
      plain =
        create_post(alice, %{post_type: "text", content: "Plain clip"}) |> attach_video(alice)

      text_only = create_post(alice, %{post_type: "text", content: "Just text"})

      ids = Streams.streams_feed(nil) |> Enum.map(& &1.id)

      assert clip.id in ids
      assert plain.id in ids
      refute text_only.id in ids
    end

    test "excludes remote (federated) authors — local videos only (issue #22)" do
      remote = create_user("sfeed_remote", "sfeed_remote@example.com") |> make_remote()
      remote_clip = create_post(remote, %{content: "Remote clip"}) |> attach_video(remote)

      local = create_user("sfeed_local", "sfeed_local@example.com")
      local_clip = create_post(local, %{content: "Local clip"}) |> attach_video(local)

      ids = Streams.streams_feed(nil) |> Enum.map(& &1.id)
      assert local_clip.id in ids
      refute remote_clip.id in ids
    end

    test "includes a remote video once a LOCAL member boosts it (issue #22, curated)" do
      remote = create_user("sfeed_rb_remote", "sfeed_rb_remote@example.com") |> make_remote()
      remote_clip = create_post(remote, %{content: "Remote clip"}) |> attach_video(remote)

      # Not boosted yet → still excluded.
      refute remote_clip.id in (Streams.streams_feed(nil) |> Enum.map(& &1.id))

      # A local member boosts it → it enters the feed.
      local = create_user("sfeed_rb_local", "sfeed_rb_local@example.com")
      Repo.insert!(%Hybridsocial.Social.Boost{post_id: remote_clip.id, identity_id: local.id})

      assert remote_clip.id in (Streams.streams_feed(nil) |> Enum.map(& &1.id))
    end

    test "a boost by a REMOTE identity does not pull a remote video into the feed" do
      remote = create_user("sfeed_rb2_r", "sfeed_rb2_r@example.com") |> make_remote()
      remote_clip = create_post(remote, %{content: "Remote clip"}) |> attach_video(remote)

      other_remote = create_user("sfeed_rb2_o", "sfeed_rb2_o@example.com") |> make_remote()

      Repo.insert!(%Hybridsocial.Social.Boost{
        post_id: remote_clip.id,
        identity_id: other_remote.id
      })

      refute remote_clip.id in (Streams.streams_feed(nil) |> Enum.map(& &1.id))
    end

    test "include_federated: true surfaces an un-boosted remote video (per-viewer opt-in)" do
      remote = create_user("sfeed_incfed_r", "sfeed_incfed_r@example.com") |> make_remote()
      remote_clip = create_post(remote, %{content: "Remote clip"}) |> attach_video(remote)

      # Default (curated) excludes it; the opt-in includes it.
      refute remote_clip.id in (Streams.streams_feed(nil) |> Enum.map(& &1.id))

      assert remote_clip.id in (Streams.streams_feed(nil, include_federated: true)
                                |> Enum.map(& &1.id))
    end

    test "excludes clips from an account the viewer has blocked" do
      viewer = create_user("sfeed_blk_v", "sfeed_blk_v@example.com")
      author = create_user("sfeed_blk_a", "sfeed_blk_a@example.com")
      clip = create_post(author, %{content: "Blocked author clip"}) |> attach_video(author)

      # Anyone else (and anon) still sees it.
      assert clip.id in (Streams.streams_feed(nil) |> Enum.map(& &1.id))

      Repo.insert!(%Hybridsocial.Social.Block{blocker_id: viewer.id, blocked_id: author.id})

      refute clip.id in (Streams.streams_feed(viewer.id) |> Enum.map(& &1.id))
      # Scoped to the viewer — a different viewer is unaffected.
      other = create_user("sfeed_blk_o", "sfeed_blk_o@example.com")
      assert clip.id in (Streams.streams_feed(other.id) |> Enum.map(& &1.id))
    end

    test "excludes clips from an account the viewer has muted" do
      viewer = create_user("sfeed_mut_v", "sfeed_mut_v@example.com")
      author = create_user("sfeed_mut_a", "sfeed_mut_a@example.com")
      clip = create_post(author, %{content: "Muted author clip"}) |> attach_video(author)

      Repo.insert!(%Hybridsocial.Social.Mute{muter_id: viewer.id, muted_id: author.id})

      refute clip.id in (Streams.streams_feed(viewer.id) |> Enum.map(& &1.id))
      assert clip.id in (Streams.streams_feed(nil) |> Enum.map(& &1.id))
    end

    test "excludes federated clips from a domain the viewer has blocked" do
      viewer = create_user("sfeed_dom_v", "sfeed_dom_v@example.com")
      remote = create_user("sfeed_dom_r", "sfeed_dom_r@example.com")

      {1, _} =
        Repo.update_all(from(i in Identity, where: i.id == ^remote.id),
          set: [is_local: false, ap_actor_url: "https://evil.example/users/x"]
        )

      clip = create_post(remote, %{content: "Remote clip"}) |> attach_video(remote)

      # With the fediverse opt-in the viewer normally sees the remote clip…
      assert clip.id in (Streams.streams_feed(viewer.id, include_federated: true)
                         |> Enum.map(& &1.id))

      {:ok, _} = Hybridsocial.Social.block_domain(viewer.id, "evil.example")

      # …but once its domain is blocked, it's gone for this viewer.
      refute clip.id in (Streams.streams_feed(viewer.id, include_federated: true)
                         |> Enum.map(& &1.id))
    end

    test "orientation: :portrait excludes horizontal and square videos" do
      alice = create_user("sfeed_orient", "sfeed_orient@example.com")

      vertical = create_post(alice, %{content: "Portrait"}) |> attach_video(alice)

      landscape =
        create_post(alice, %{content: "Landscape"})
        |> attach_video(alice, width: 1920, height: 1080)

      square =
        create_post(alice, %{content: "Square"}) |> attach_video(alice, width: 1080, height: 1080)

      ids = Streams.streams_feed(nil, orientation: :portrait) |> Enum.map(& &1.id)
      assert vertical.id in ids
      refute landscape.id in ids
      refute square.id in ids
    end

    test "the default includes horizontal, square, and unknown-dimension videos" do
      alice = create_user("sfeed_all", "sfeed_all@example.com")

      vertical = create_post(alice, %{content: "Portrait"}) |> attach_video(alice)

      landscape =
        create_post(alice, %{content: "Landscape 640x360"})
        |> attach_video(alice, width: 640, height: 360)

      square =
        create_post(alice, %{content: "Square"}) |> attach_video(alice, width: 1080, height: 1080)

      nodim =
        create_post(alice, %{content: "No dims"}) |> attach_video(alice, width: nil, height: nil)

      ids = Streams.streams_feed(nil) |> Enum.map(& &1.id)
      assert vertical.id in ids
      assert landscape.id in ids
      assert square.id in ids
      assert nodim.id in ids
    end

    test "the default still enforces the minimum duration" do
      alice = create_user("sfeed_all_dur", "sfeed_all_dur@example.com")

      short =
        create_post(alice, %{content: "Short landscape"})
        |> attach_video(alice, width: 640, height: 360, duration: 5.0)

      ids = Streams.streams_feed(nil) |> Enum.map(& &1.id)
      refute short.id in ids
    end

    test "orientation: :portrait excludes videos with unknown (NULL) dimensions" do
      alice = create_user("sfeed_nodim", "sfeed_nodim@example.com")

      nodim =
        create_post(alice, %{content: "No dims"}) |> attach_video(alice, width: nil, height: nil)

      ids = Streams.streams_feed(nil, orientation: :portrait) |> Enum.map(& &1.id)
      refute nodim.id in ids
    end

    test "excludes videos shorter than the minimum duration" do
      alice = create_user("sfeed_dur", "sfeed_dur@example.com")
      short = create_post(alice, %{content: "Too short"}) |> attach_video(alice, duration: 5.0)

      ids = Streams.streams_feed(nil) |> Enum.map(& &1.id)
      refute short.id in ids
    end

    test "a clip at or above the default minimum (10s) qualifies" do
      alice = create_user("sfeed_dur10", "sfeed_dur10@example.com")
      # 12s — under the old hardcoded 15s floor, over the new 10s default.
      clip = create_post(alice, %{content: "12s clip"}) |> attach_video(alice, duration: 12.0)

      ids = Streams.streams_feed(nil) |> Enum.map(& &1.id)
      assert clip.id in ids
    end

    test "the minimum duration is tunable — raising it excludes an otherwise-qualifying clip" do
      alice = create_user("sfeed_durcfg", "sfeed_durcfg@example.com")
      clip = create_post(alice, %{content: "12s clip"}) |> attach_video(alice, duration: 12.0)

      ids = Streams.streams_feed(nil, min_duration_seconds: 20) |> Enum.map(& &1.id)
      refute clip.id in ids
    end

    test "excludes sensitive and content-warned posts" do
      alice = create_user("sfeed_cw", "sfeed_cw@example.com")
      nsfw = create_post(alice, %{content: "nsfw", sensitive: true}) |> attach_video(alice)
      cw = create_post(alice, %{content: "cw", spoiler_text: "spoiler"}) |> attach_video(alice)

      ids = Streams.streams_feed(nil) |> Enum.map(& &1.id)
      refute nsfw.id in ids
      refute cw.id in ids
    end

    test "returns only public posts" do
      alice = create_user("sfeed_pub", "sfeed_pub@example.com")

      create_post(alice, %{visibility: "followers", content: "Private clip"})
      |> attach_video(alice)

      assert Streams.streams_feed(nil) == []
    end

    test "excludes deleted posts" do
      alice = create_user("sfeed_del", "sfeed_del@example.com")
      post = create_post(alice, %{content: "Deleted clip"}) |> attach_video(alice)

      post |> Post.soft_delete_changeset() |> Repo.update!()

      ids = Streams.streams_feed(nil) |> Enum.map(& &1.id)
      refute post.id in ids
    end

    test "supports pagination with limit" do
      alice = create_user("sfeed_lim", "sfeed_lim@example.com")

      for i <- 1..5 do
        create_post(alice, %{content: "Clip #{i}"}) |> attach_video(alice)
      end

      posts = Streams.streams_feed(nil, limit: 3)
      assert length(posts) == 3
    end

    test "sort: newest and oldest order by recency" do
      alice = create_user("sfeed_sort", "sfeed_sort@example.com")

      older = create_post(alice, %{content: "Older"}) |> attach_video(alice)
      # Force a strictly later timestamp so ordering is deterministic.
      newer = create_post(alice, %{content: "Newer"}) |> attach_video(alice)

      Repo.update_all(
        from(p in Post, where: p.id == ^older.id),
        set: [inserted_at: ~U[2020-01-01 00:00:00.000000Z]]
      )

      newest = Streams.streams_feed(nil, sort: "newest") |> Enum.map(& &1.id)
      oldest = Streams.streams_feed(nil, sort: "oldest") |> Enum.map(& &1.id)

      assert Enum.find_index(newest, &(&1 == newer.id)) <
               Enum.find_index(newest, &(&1 == older.id))

      assert Enum.find_index(oldest, &(&1 == older.id)) <
               Enum.find_index(oldest, &(&1 == newer.id))
    end

    test "sort: newest paginates accurately via the keyset cursor (no dupes, no gaps)" do
      alice = create_user("sfeed_page", "sfeed_page@example.com")

      p1 = create_post(alice, %{content: "one"}) |> attach_video(alice)
      p2 = create_post(alice, %{content: "two"}) |> attach_video(alice)
      p3 = create_post(alice, %{content: "three"}) |> attach_video(alice)

      # Strictly increasing times → newest order is [p3, p2, p1].
      for {p, day} <- [{p1, 1}, {p2, 2}, {p3, 3}] do
        Repo.update_all(from(x in Post, where: x.id == ^p.id),
          set: [inserted_at: DateTime.new!(Date.new!(2020, 1, day), ~T[00:00:00.000000])]
        )
      end

      page1 = Streams.streams_feed(nil, sort: "newest", limit: 2) |> Enum.map(& &1.id)
      assert page1 == [p3.id, p2.id]

      page2 =
        Streams.streams_feed(nil, sort: "newest", limit: 2, max_id: List.last(page1))
        |> Enum.map(& &1.id)

      # Continues from the boundary with no overlap and no skipped rows.
      assert page2 == [p1.id]
    end

    test "sort: oldest paginates forward via the min_id keyset cursor" do
      alice = create_user("sfeed_page_old", "sfeed_page_old@example.com")

      p1 = create_post(alice, %{content: "one"}) |> attach_video(alice)
      p2 = create_post(alice, %{content: "two"}) |> attach_video(alice)
      p3 = create_post(alice, %{content: "three"}) |> attach_video(alice)

      for {p, day} <- [{p1, 1}, {p2, 2}, {p3, 3}] do
        Repo.update_all(from(x in Post, where: x.id == ^p.id),
          set: [inserted_at: DateTime.new!(Date.new!(2020, 1, day), ~T[00:00:00.000000])]
        )
      end

      page1 = Streams.streams_feed(nil, sort: "oldest", limit: 2) |> Enum.map(& &1.id)
      assert page1 == [p1.id, p2.id]

      page2 =
        Streams.streams_feed(nil, sort: "oldest", limit: 2, min_id: List.last(page1))
        |> Enum.map(& &1.id)

      assert page2 == [p3.id]
    end

    test "q: filters by phrase or hashtag in the post body" do
      alice = create_user("sfeed_q", "sfeed_q@example.com")

      match = create_post(alice, %{content: "Sunset over #Gaza tonight"}) |> attach_video(alice)
      other = create_post(alice, %{content: "A cooking clip"}) |> attach_video(alice)

      by_phrase = Streams.streams_feed(nil, q: "sunset") |> Enum.map(& &1.id)
      assert match.id in by_phrase
      refute other.id in by_phrase

      by_tag = Streams.streams_feed(nil, q: "#gaza") |> Enum.map(& &1.id)
      assert match.id in by_tag
      refute other.id in by_tag
    end

    test "q: blank query is ignored (returns the full feed)" do
      alice = create_user("sfeed_blank", "sfeed_blank@example.com")
      post = create_post(alice, %{content: "Anything"}) |> attach_video(alice)

      ids = Streams.streams_feed(nil, q: "   ") |> Enum.map(& &1.id)
      assert post.id in ids
    end
  end
end

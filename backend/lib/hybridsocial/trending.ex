defmodule Hybridsocial.Trending do
  @moduledoc """
  Trending context. Computes and retrieves trending posts, hashtags, and links.
  Uses precomputed data stored in the trending_data table.

  Computation runs in PostgreSQL: it scores hashtags by
  `post_count * ln(unique_accounts + 1)` (volume weighted by distinct
  authors) and also stores the "people talking" count and a per-day
  sparkline. An earlier OpenSearch aggregation path was removed because
  it was never reachable (dead guard) and, being volume-only with no
  author count or sparkline, would have regressed the UI if enabled.
  """
  import Ecto.Query

  alias Hybridsocial.Feeds.Visibility
  alias Hybridsocial.Moderation.BlockedHashtag
  alias Hybridsocial.Repo
  alias Hybridsocial.Search.TrendingData
  alias Hybridsocial.Social.{Post, Hashtag}

  @default_limit 20
  @max_limit 40
  @half_life_hours 6
  @min_unique_accounts_posts 3

  # Hashtag eligibility:
  #   * `trending_hashtag_window_hours` — how far back to look. Defaults
  #     to 168h (one week) so low-volume instances don't end up with an
  #     empty trending list whenever a 24h window happens to be quiet.
  #   * `trending_hashtag_min_accounts` — how many distinct authors must
  #     have used the tag in that window. Defaults to 2 (rewards broad
  #     usage over a single chatty account). Tiny instances should set
  #     this to 1 via Admin → Settings so any actively-used tag surfaces.
  defp hashtag_window_hours,
    do: Hybridsocial.Config.get("trending_hashtag_window_hours", 168)

  defp hashtag_min_accounts,
    do: Hybridsocial.Config.get("trending_hashtag_min_accounts", 2)

  # Floor on raw post count so a tag used once doesn't surface in
  # trending. On instances tiny enough that `min_accounts` is dropped
  # to 1, every tag-used-once would otherwise qualify and the
  # trending list ends up listing every hashtag the instance has
  # ever seen. Defaults to 2 — single-use tags are noise; two posts
  # is the smallest signal that the author cares about it.
  defp hashtag_min_posts,
    do: Hybridsocial.Config.get("trending_hashtag_min_posts", 2)

  @doc """
  Computes trending posts based on recent engagement velocity,
  account diversity, and time decay. Stores results in trending_data.
  """
  def compute_trending_posts do
    pg_compute_trending_posts()
  end

  @doc """
  Computes trending hashtags based on usage in the last 24 hours.
  """
  def compute_trending_hashtags do
    pg_compute_trending_hashtags()
  end

  @doc """
  Returns precomputed trending posts with limit/offset.
  """
  def get_trending_posts(opts \\ []) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    trending =
      TrendingData
      |> where([t], t.type == "post")
      |> order_by([t], desc: t.score)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    post_ids = Enum.map(trending, & &1.target_id)

    # Exclude hidden posts at read time too, not just at compute
    # time — a post that got admin-hidden after trending was computed
    # should disappear from the feed immediately without waiting for
    # the next compute tick (5 min default).
    posts =
      Post
      |> where([p], p.id in ^post_ids)
      |> where([p], is_nil(p.deleted_at))
      |> where([p], is_nil(p.hidden_at))
      |> where([p], p.identity_id not in subquery(Visibility.publicly_hidden_author_ids()))
      |> Visibility.apply_blocked_hashtag_filter()
      |> Repo.all()
      |> Repo.preload(:identity)
      |> Map.new(&{&1.id, &1})

    Enum.map(trending, fn td ->
      %{trending: td, post: Map.get(posts, td.target_id)}
    end)
    |> Enum.filter(fn %{post: post} -> post != nil end)
  end

  @doc """
  Returns precomputed trending hashtags with limit/offset.
  """
  def get_trending_hashtags(opts \\ []) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    # Filtered at read time rather than at compute time, so a block or unblock
    # takes effect immediately instead of on the next compute tick.
    TrendingData
    |> where([t], t.type == "hashtag")
    |> where([t], t.target_id not in subquery(from(b in BlockedHashtag, select: b.name)))
    |> order_by([t], desc: t.score)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns trending links. Placeholder for now.
  """
  def get_trending_links(_opts \\ []) do
    []
  end

  @doc """
  Removes trending_data older than 48 hours.
  """
  def cleanup_old_trending do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-48, :hour)
      |> DateTime.truncate(:microsecond)

    TrendingData
    |> where([t], t.computed_at < ^cutoff)
    |> Repo.delete_all()

    :ok
  end

  # --- PostgreSQL Implementations ---

  defp pg_compute_trending_posts do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    cutoff = DateTime.add(now, -24, :hour)

    results =
      Post
      |> where([p], is_nil(p.deleted_at))
      # Admin-hidden posts drop out of Explore/global timelines, so
      # they should drop out of trending too — otherwise a
      # hidden-but-still-engaging post could surface on /explore via
      # the trending row.
      |> where([p], is_nil(p.hidden_at))
      |> where([p], p.visibility == "public")
      |> where([p], p.published_at >= ^cutoff)
      |> where([p], p.identity_id not in subquery(Visibility.publicly_hidden_author_ids()))
      |> Visibility.apply_blocked_hashtag_filter()
      |> join(:left, [p], r in "reactions", on: r.post_id == p.id and r.inserted_at >= ^cutoff)
      |> join(:left, [p, _r], b in "boosts",
        on: b.post_id == p.id and b.inserted_at >= ^cutoff and is_nil(b.deleted_at)
      )
      |> join(:left, [p, _r, _b], rep in "posts",
        on: rep.parent_id == p.id and rep.inserted_at >= ^cutoff and is_nil(rep.deleted_at)
      )
      |> group_by([p, _r, _b, _rep], p.id)
      |> select([p, r, b, rep], %{
        post_id: p.id,
        published_at: p.published_at,
        reaction_count: count(r.id, :distinct),
        boost_count: count(b.id, :distinct),
        reply_count: count(rep.id, :distinct),
        unique_reactors: fragment("COUNT(DISTINCT ?)", r.identity_id),
        unique_boosters: fragment("COUNT(DISTINCT ?)", b.identity_id),
        unique_repliers: fragment("COUNT(DISTINCT ?)", rep.identity_id)
      })
      |> Repo.all()

    # Clear old trending posts
    TrendingData
    |> where([t], t.type == "post")
    |> Repo.delete_all()

    # Compute scores and insert
    trending_entries =
      results
      |> Enum.map(fn row ->
        approx_unique = row.unique_reactors + row.unique_boosters + row.unique_repliers

        total_engagement = row.reaction_count + row.boost_count + row.reply_count
        hours_old = DateTime.diff(now, row.published_at, :second) / 3600.0
        decay = :math.pow(0.5, hours_old / @half_life_hours)
        score = total_engagement * decay * :math.log(max(approx_unique, 1) + 1)

        %{
          row: row,
          score: score,
          approx_unique: approx_unique,
          total_engagement: total_engagement
        }
      end)
      |> Enum.filter(fn %{approx_unique: u} -> u >= @min_unique_accounts_posts end)
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(100)

    Enum.each(trending_entries, fn %{
                                     row: row,
                                     score: score,
                                     total_engagement: eng,
                                     approx_unique: uniq
                                   } ->
      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "post",
        target_id: row.post_id,
        score: score,
        computed_at: now,
        metadata: %{
          engagement: eng,
          unique_accounts: uniq
        }
      })
      |> Repo.insert!()
    end)

    :ok
  end

  defp pg_compute_trending_hashtags do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    window_hours = hashtag_window_hours()
    min_accounts = hashtag_min_accounts()
    min_posts = hashtag_min_posts()
    cutoff = DateTime.add(now, -window_hours, :hour)

    results =
      Hashtag
      |> join(:inner, [h], ph in "post_hashtags", on: ph.hashtag_id == h.id)
      |> join(:inner, [_h, ph], p in Post,
        on:
          p.id == ph.post_id and p.inserted_at >= ^cutoff and is_nil(p.deleted_at) and
            is_nil(p.hidden_at)
      )
      # Moderated authors must not be able to push a tag into trending: a few
      # flooding accounts are otherwise enough to fill the list on their own.
      |> where(
        [_h, _ph, p],
        p.identity_id not in subquery(Visibility.publicly_hidden_author_ids())
      )
      |> group_by([h, _ph, _p], [h.id, h.name])
      |> select([h, _ph, p], %{
        hashtag_id: h.id,
        name: h.name,
        post_count: count(p.id, :distinct),
        unique_accounts: fragment("COUNT(DISTINCT ?)", p.identity_id)
      })
      |> having(
        [_h, _ph, p],
        fragment("COUNT(DISTINCT ?)", p.identity_id) >= ^min_accounts and
          count(p.id, :distinct) >= ^min_posts
      )
      |> Repo.all()

    # Fetch a 7-hour sparkline history for every trending hashtag in
    # one round trip. date_trunc + GROUP BY pairs each hashtag with its
    # per-hour post count over the last 7h; we then reshape into a
    # 7-element array per hashtag, zero-filling buckets with no posts.
    hashtag_ids = Enum.map(results, & &1.hashtag_id)
    history_by_id = fetch_hashtag_history(hashtag_ids, now)

    # Clear old trending hashtags
    TrendingData
    |> where([t], t.type == "hashtag")
    |> Repo.delete_all()

    # Compute scores and insert
    results
    |> Enum.each(fn row ->
      score = row.post_count * :math.log(row.unique_accounts + 1)

      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "hashtag",
        target_id: row.name,
        score: score,
        computed_at: now,
        metadata: %{
          post_count: row.post_count,
          unique_accounts: row.unique_accounts,
          history: Map.get(history_by_id, row.hashtag_id, List.duplicate(0, 7))
        }
      })
      |> Repo.insert!()
    end)

    :ok
  end

  # Returns %{hashtag_id => [d-6, d-5, ..., d-0]} where each entry is
  # the count of distinct posts carrying that hashtag within that day
  # (UTC). Daily buckets over the past 7 days line up with the
  # default eligibility window (168 h), so a tag posted twice on
  # different days now produces a line with actual shape — the older
  # 7-hour version was almost always all-zero on small instances
  # because the posts were older than 7 hours, and the rendered
  # sparkline degenerated into a flat line at the chart edge.
  defp fetch_hashtag_history([], _now), do: %{}

  defp fetch_hashtag_history(hashtag_ids, now) do
    history_cutoff = DateTime.add(now, -7, :day)

    # Day ordinals 0..6 where 0 is six days ago and 6 is today (UTC).
    # Floor `now` to the day via Unix seconds, then back up six days
    # so the last index is today and the first is one week back.
    seconds_per_day = 86_400
    current_day_unix = DateTime.to_unix(now) - rem(DateTime.to_unix(now), seconds_per_day)
    base_day = DateTime.from_unix!(current_day_unix - 6 * seconds_per_day)

    # `post_hashtags` is queried as a raw table source (no schema),
    # so Ecto has no type info for `ph.hashtag_id`. Without an
    # explicit `type/2` cast, Postgrex tries to encode the UUID
    # strings as raw 16-byte binaries and crashes. Explicit cast
    # tells it the array is `{:array, Ecto.UUID}`.
    rows =
      Post
      |> join(:inner, [p], ph in "post_hashtags", on: ph.post_id == p.id)
      |> where([p, ph], ph.hashtag_id in type(^hashtag_ids, {:array, Ecto.UUID}))
      |> where([p, _ph], p.inserted_at >= ^history_cutoff and is_nil(p.deleted_at))
      |> group_by([p, ph], [ph.hashtag_id, fragment("date_trunc('day', ?)", p.inserted_at)])
      |> select([p, ph], %{
        # `post_hashtags` is queried as a raw table source, so without
        # an explicit `type/2` cast Postgrex returns `hashtag_id` as
        # a 16-byte binary blob. The caller's keys are string UUIDs
        # from the `Hashtag` schema, so every Map.get fell through
        # to the default `[0,0,0,0,0,0,0]` and the sparkline went
        # flat. Cast in the SELECT so the keys match.
        hashtag_id: type(ph.hashtag_id, Ecto.UUID),
        bucket: fragment("date_trunc('day', ?)", p.inserted_at),
        count: count(p.id, :distinct)
      })
      |> Repo.all()

    Enum.reduce(rows, %{}, fn row, acc ->
      # `date_trunc('day', inserted_at)` returns a NaiveDateTime
      # because `inserted_at` is `timestamp without time zone`. Cast
      # to UTC before diffing — DateTime.diff/3 raises on mixed
      # struct types.
      bucket_dt =
        case row.bucket do
          %DateTime{} = dt -> dt
          %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC")
        end

      bucket_index = DateTime.diff(bucket_dt, base_day, :second) |> div(seconds_per_day)

      if bucket_index in 0..6 do
        series = Map.get(acc, row.hashtag_id) || List.duplicate(0, 7)
        Map.put(acc, row.hashtag_id, List.replace_at(series, bucket_index, row.count))
      else
        acc
      end
    end)
  end

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp parse_offset(opts) do
    opts
    |> Keyword.get(:offset, 0)
    |> max(0)
  end
end

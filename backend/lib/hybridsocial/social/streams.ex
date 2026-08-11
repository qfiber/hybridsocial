defmodule Hybridsocial.Social.Streams do
  @moduledoc """
  Context for video stream view tracking and the streams feed.
  """
  import Ecto.Query

  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{StreamView, Post}

  @default_limit 20
  @max_limit 40
  # Default minimum clip length (seconds) for the streams feed when the
  # `streams_min_duration_seconds` setting isn't configured.
  @default_min_duration 10

  @doc """
  Records a view event for a video stream post.
  """
  def record_view(post_id, identity_id, attrs) do
    %StreamView{}
    |> StreamView.changeset(
      Map.merge(attrs, %{
        "post_id" => post_id,
        "identity_id" => identity_id
      })
    )
    |> Repo.insert()
  end

  @doc """
  Returns view statistics for a given post.

  Returns a map with:
    - total_views
    - unique_viewers
    - avg_watch_duration
    - completion_rate
    - replay_rate
  """
  def get_view_stats(post_id) do
    query =
      StreamView
      |> where([sv], sv.post_id == ^post_id)

    total_views = Repo.aggregate(query, :count)

    if total_views == 0 do
      %{
        total_views: 0,
        unique_viewers: 0,
        avg_watch_duration: 0.0,
        completion_rate: 0.0,
        replay_rate: 0.0
      }
    else
      unique_viewers =
        query
        |> where([sv], not is_nil(sv.identity_id))
        |> select([sv], count(sv.identity_id, :distinct))
        |> Repo.one()

      avg_watch_duration =
        query
        |> select([sv], avg(sv.watch_duration))
        |> Repo.one() || 0.0

      completed_count =
        query
        |> where([sv], sv.completed == true)
        |> Repo.aggregate(:count)

      replayed_count =
        query
        |> where([sv], sv.replayed == true)
        |> Repo.aggregate(:count)

      %{
        total_views: total_views,
        unique_viewers: unique_viewers,
        avg_watch_duration: avg_watch_duration |> to_float(),
        completion_rate: to_float(completed_count / total_views * 100),
        replay_rate: to_float(replayed_count / total_views * 100)
      }
    end
  end

  @doc """
  Returns the video streams feed: any public post carrying a qualifying
  video attachment, ordered by engagement (reaction_count) then recency,
  cursor paginated.
  """
  def streams_feed(viewer_id, opts \\ []) do
    limit = parse_limit(opts)
    min_duration = Keyword.get(opts, :min_duration_seconds) || min_duration_seconds()
    search = normalize_search(Keyword.get(opts, :q))
    # :all (the default) surfaces clips of any orientation/size — a 640x360
    # horizontal upload belongs in the feed just as much as a 9:16 one, and
    # defaulting the other way is what hid them (only height > width qualified).
    # :portrait is an explicit opt-in for a strictly-vertical feed.
    orientation = Keyword.get(opts, :orientation, :all)
    # Per-user opt-in (a toggle on Streams): when true, drop the locality
    # filter entirely so this viewer sees EVERY public fediverse video, not just
    # local + locally-boosted. Off by default → the curated feed below.
    include_federated = Keyword.get(opts, :include_federated, false)

    # Streams surfaces public video to everyone, including signed-out
    # viewers. By default membership is "a public post carrying a qualifying
    # video whose author is LOCAL, OR that a LOCAL member has boosted" — so a
    # federated video only enters the feed once someone here deliberately
    # reblogs it (curated, not the whole fediverse). A viewer who flips the
    # `include_federated` toggle instead sees all public fediverse videos. See
    # `apply_local_or_boosted/1` and issue #22. Excludes:
    #   - remote/federated authors that no local member boosted.
    #   - sensitive (NSFW) posts
    #   - posts with a content warning (spoiler_text)
    #   - by orientation (see `filter_by_qualifying_video`): the default
    #     `:all` accepts any clip — horizontal, square, portrait, or unknown
    #     dimensions; `:portrait` narrows to strictly vertical clips with
    #     known dimensions (height > width).
    #   - posts whose video attachment is shorter than `min_duration`
    #     seconds (admin-tunable via `streams_min_duration_seconds`, default
    #     10) — the format is meant for short *clips*, not micro-bursts that
    #     flash by before the page can render the next one. Applies in both
    #     orientation modes.
    # The video predicate joins the media table (duration + dimensions
    # live there per-attachment); the EXISTS form keeps the join from
    # multiplying rows on posts with multiple media.
    query =
      Post
      |> join(:inner, [p], i in Identity, on: i.id == p.identity_id)
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.deleted_at))
      |> where([p], p.sensitive == false)
      |> where([p], is_nil(p.spoiler_text) or p.spoiler_text == "")
      |> apply_viewer_blocks(viewer_id)
      |> maybe_apply_locality(include_federated)
      |> filter_by_qualifying_video(orientation, min_duration)
      |> apply_search(search)
      |> apply_cursor_filters(opts)
      |> apply_sort(Keyword.get(opts, :sort))
      |> limit(^limit)
      |> preload(:identity)

    Repo.all(query)
  end

  # --- Private helpers ---

  # `include_federated: true` (the per-viewer opt-in) skips the locality filter
  # so every public fediverse video qualifies; otherwise apply the curated
  # local-or-boosted rule.
  defp maybe_apply_locality(query, true), do: query
  defp maybe_apply_locality(query, _false), do: apply_local_or_boosted(query)

  # Keep a post if its author is local, OR a local member has boosted it (an
  # active, non-deleted boost by a local identity). The latter lets curated
  # federated video enter Streams without opening the feed to the whole
  # fediverse. `[p, i]` — i is the author Identity joined above.
  defp apply_local_or_boosted(query) do
    where(
      query,
      [p, i],
      i.is_local == true or
        fragment(
          "EXISTS (SELECT 1 FROM boosts b JOIN identities bi ON bi.id = b.identity_id WHERE b.post_id = ? AND b.deleted_at IS NULL AND bi.is_local = TRUE)",
          p.id
        )
    )
  end

  # A signed-in viewer never sees clips they've moderated away — this is the
  # safety net for the `include_federated` opt-in: once the whole fediverse can
  # surface here, the viewer needs the same block/mute/domain controls the rest
  # of the app already honors. Applies unconditionally (not just for federated),
  # since a blocked local author's clip shouldn't appear either. Signed-out
  # viewers (nil) have nothing to filter on.
  defp apply_viewer_blocks(query, nil), do: query

  defp apply_viewer_blocks(query, viewer_id) do
    query
    |> Hybridsocial.Feeds.Visibility.apply_block_filter(viewer_id)
    |> Hybridsocial.Feeds.Visibility.apply_mute_filter(viewer_id)
    |> apply_domain_block_filter(viewer_id)
  end

  # Drop clips whose REMOTE author lives on a domain the viewer has blocked
  # (`user_domain_blocks`). Identities carry no domain column, so derive the
  # host from `ap_actor_url` (`https://host/…` → split_part …, '/', 3, then
  # strip any `:port`), matching the lowercased domain the block stores. Local
  # authors and rows without an actor URL are always kept.
  defp apply_domain_block_filter(query, viewer_id) do
    where(
      query,
      [p, i],
      i.is_local == true or is_nil(i.ap_actor_url) or
        not fragment(
          "EXISTS (SELECT 1 FROM user_domain_blocks udb WHERE udb.identity_id = ? AND udb.domain = lower(split_part(split_part(?, '/', 3), ':', 1)))",
          type(^viewer_id, Ecto.UUID),
          i.ap_actor_url
        )
    )
  end

  # Minimum clip length (seconds) for the streams feed — admin-tunable
  # via the `streams_min_duration_seconds` setting so an instance can include
  # shorter clips or require longer ones. Values are stored untyped in Config,
  # so coerce a stored string back to a number.
  defp min_duration_seconds do
    case Hybridsocial.Config.get("streams_min_duration_seconds", @default_min_duration) do
      n when is_number(n) ->
        n

      s when is_binary(s) ->
        case Float.parse(s) do
          {f, _} -> f
          :error -> @default_min_duration
        end

      _ ->
        @default_min_duration
    end
  end

  # Portrait: strictly vertical clips with known dimensions. Opt-in only.
  defp filter_by_qualifying_video(query, :portrait, min_duration) do
    where(
      query,
      [p],
      fragment(
        "EXISTS (SELECT 1 FROM media m WHERE m.post_id = ? AND m.deleted_at IS NULL AND m.content_type LIKE 'video/%' AND m.width IS NOT NULL AND m.height IS NOT NULL AND m.height > m.width AND (m.duration IS NULL OR m.duration >= ?))",
        p.id,
        ^min_duration
      )
    )
  end

  # All orientations (the default): any video clip, regardless of dimensions —
  # horizontal, square, portrait, or dimensions we never captured.
  defp filter_by_qualifying_video(query, _all, min_duration) do
    where(
      query,
      [p],
      fragment(
        "EXISTS (SELECT 1 FROM media m WHERE m.post_id = ? AND m.deleted_at IS NULL AND m.content_type LIKE 'video/%' AND (m.duration IS NULL OR m.duration >= ?))",
        p.id,
        ^min_duration
      )
    )
  end

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp apply_cursor_filters(query, opts) do
    # The frontend sends the last item's id as max_id (desc feeds) or min_id
    # (the asc "oldest" feed); either way it's just the boundary row. Resolve it
    # and keyset-compare on the SAME key the sort orders by.
    cursor_id = Keyword.get(opts, :max_id) || Keyword.get(opts, :min_id)
    apply_keyset(query, Keyword.get(opts, :sort), cursor_id)
  end

  defp apply_keyset(query, _sort, nil), do: query

  defp apply_keyset(query, sort, cursor_id) do
    case Repo.one(
           from(p in Post,
             where: p.id == ^cursor_id,
             select: {p.reaction_count, p.inserted_at, p.id}
           )
         ) do
      nil -> query
      boundary -> keyset_where(query, sort, boundary)
    end
  end

  # Keyset compares mirror `apply_sort` exactly (same key, same direction, same
  # id tiebreak) so pagination is accurate — post ids are random UUIDv4, so the
  # old `p.id < max_id` returned an arbitrary slice and the feed froze.
  defp keyset_where(query, "newest", {_rc, ia, id}) do
    where(
      query,
      [p],
      fragment("(?, ?) < (?, ?)", p.inserted_at, p.id, ^ia, type(^id, Ecto.UUID))
    )
  end

  defp keyset_where(query, "oldest", {_rc, ia, id}) do
    where(
      query,
      [p],
      fragment("(?, ?) > (?, ?)", p.inserted_at, p.id, ^ia, type(^id, Ecto.UUID))
    )
  end

  defp keyset_where(query, _trending, {rc, ia, id}) do
    where(
      query,
      [p],
      fragment(
        "(?, ?, ?) < (?, ?, ?)",
        p.reaction_count,
        p.inserted_at,
        p.id,
        ^rc,
        ^ia,
        type(^id, Ecto.UUID)
      )
    )
  end

  # Timeline ordering the viewer picks: trending (engagement-weighted, the
  # default), newest, or oldest. The `id` tiebreak makes the order total and
  # matches the keyset cursor above.
  defp apply_sort(query, "newest"), do: order_by(query, [p], desc: p.inserted_at, desc: p.id)
  defp apply_sort(query, "oldest"), do: order_by(query, [p], asc: p.inserted_at, asc: p.id)

  defp apply_sort(query, _trending),
    do: order_by(query, [p], desc: p.reaction_count, desc: p.inserted_at, desc: p.id)

  # Free-text filter over the post body. Hashtags live literally in the
  # content (e.g. "#gaza"), so a single case-insensitive match covers both
  # plain phrases and tag searches; user wildcards are escaped so `%`/`_`
  # are treated literally.
  defp normalize_search(q) when is_binary(q) do
    case String.trim(q) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_search(_), do: nil

  defp apply_search(query, nil), do: query

  defp apply_search(query, q) do
    pattern = "%" <> escape_like(q) <> "%"
    where(query, [p], ilike(p.content, ^pattern))
  end

  defp escape_like(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1
  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(_), do: 0.0
end

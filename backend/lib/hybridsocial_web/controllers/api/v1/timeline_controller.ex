defmodule HybridsocialWeb.Api.V1.TimelineController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Feeds
  alias Hybridsocial.Feeds.Snapshot
  alias Hybridsocial.Trending.ExploreFeed
  alias Hybridsocial.Cache
  alias HybridsocialWeb.Serializers.PostSerializer
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]
  alias HybridsocialWeb.Compat
  alias HybridsocialWeb.Helpers.TimelineAccess

  # Short cache window for the *serialized* first page of the public /
  # global feeds. The heavy cost is the query plus per-post serialization
  # (link-preview cards, media, counts) — for the global feed that can
  # spike to seconds on a cold cache. We cache the JSON-ready payload
  # (not Post structs, which don't survive the cache's JSON round-trip),
  # so a warm load skips both the query and serialization. Live updates
  # still arrive over the SSE stream, so this only shortcuts the initial
  # load; a 30s TTL keeps it fresh enough without an invalidation hook.
  @feed_cache_ttl 30

  defp timeline_access, do: TimelineAccess.level()
  defp check_timeline_access(conn, level), do: TimelineAccess.check(conn, level)
  defp deny_access(conn), do: TimelineAccess.deny(conn)

  @doc "GET /api/v1/timelines/home - Authenticated home timeline"
  def home(conn, params) do
    identity = conn.assigns.current_identity
    opts = parse_pagination_params(params)

    opts =
      case params["algorithm"] do
        "true" -> Keyword.put(opts, :algorithm, "algorithmic")
        "trending" -> Keyword.put(opts, :algorithm, "trending")
        "algorithmic" -> Keyword.put(opts, :algorithm, "algorithmic")
        _ -> opts
      end

    identity_id = identity.id
    cache_key = "feed:home:ser:#{identity_id}:#{Keyword.get(opts, :algorithm, "chrono")}"

    posts =
      cached_feed(cache_key, first_page?(params), fn ->
        entries = Feeds.home_timeline(identity_id, opts)

        if Keyword.get(opts, :algorithm) do
          PostSerializer.serialize_many(entries, current_identity_id: identity_id)
        else
          serialize_timeline_entries(entries, identity_id)
        end
      end)

    conn
    |> put_link_headers(posts, "/api/v1/timelines/home")
    |> put_status(:ok)
    |> Compat.json(posts, :statuses)
  end

  @doc "GET /api/v1/timelines/public - Public timeline (optional auth)"
  def public(conn, params) do
    # `local=false` serves remote posts, so it needs the same access as Global.
    level = if Map.get(params, "local", "true") == "true", do: :local, else: :global

    case check_timeline_access(conn, level) do
      :denied ->
        deny_access(conn)

      :ok ->
        viewer_id =
          case conn.assigns[:current_identity] do
            nil -> nil
            identity -> identity.id
          end

        opts =
          parse_pagination_params(params)
          |> Keyword.merge(
            include_replies: params["include_replies"] == "true",
            local_only: Map.get(params, "local", "true") == "true",
            viewer_id: viewer_id
          )
          |> maybe_put_public_sort(params["sort"] || params["algorithm"])

        cache_key =
          "feed:public:ser:#{viewer_id || "anon"}:#{opts[:local_only]}:#{opts[:include_replies]}:#{Keyword.get(opts, :sort, "newest")}"

        serialized =
          cached_feed(cache_key, first_page?(params), fn ->
            opts
            |> Feeds.public_timeline()
            |> PostSerializer.serialize_many(current_identity_id: viewer_id)
          end)

        conn
        |> put_link_headers(serialized, "/api/v1/timelines/public")
        |> put_status(:ok)
        |> Compat.json(serialized, :statuses)
    end
  end

  @doc "GET /api/v1/timelines/tag/:hashtag - Hashtag timeline (optional auth)"
  def hashtag(conn, %{"hashtag" => hashtag} = params) do
    case check_timeline_access(conn, :local) do
      :denied ->
        deny_access(conn)

      :ok ->
        viewer_id =
          case conn.assigns[:current_identity] do
            nil -> nil
            identity -> identity.id
          end

        opts =
          parse_pagination_params(params)
          |> Keyword.put(:viewer_id, viewer_id)

        serialized =
          cond do
            # Snapshots are shared with logged-in members, so they hold locked
            # accounts' public posts. Anonymous requests get a filtered query
            # with its own short cache instead.
            is_nil(viewer_id) ->
              cached_feed(
                "feed:tag:anon:#{hashtag}:#{Keyword.get(opts, :limit)}",
                first_page?(params),
                fn ->
                  hashtag
                  |> Feeds.hashtag_timeline(opts)
                  |> PostSerializer.serialize_many(current_identity_id: nil)
                end
              )

            first_page?(params) ->
              # Hashtag feeds are as expensive as the global feed and had no
              # cache at all. Popular tags are prewarmed by
              # Feeds.PrewarmWorker; long-tail tags fall back to a lazy
              # snapshot on first view. Either way, layer viewer state on top.
              Snapshot.hashtag_key(hashtag)
              |> Snapshot.fetch(fn ->
                hashtag
                |> Feeds.hashtag_timeline(viewer_id: nil, include_locked: true)
                |> PostSerializer.serialize_many(current_identity_id: nil)
              end)
              |> PostSerializer.apply_viewer_state(viewer_id)

            true ->
              hashtag
              |> Feeds.hashtag_timeline(opts)
              |> PostSerializer.serialize_many(current_identity_id: viewer_id)
          end

        conn
        |> put_link_headers(serialized, "/api/v1/timelines/tag/#{hashtag}")
        |> put_status(:ok)
        |> Compat.json(serialized, :statuses)
    end
  end

  @doc "GET /api/v1/timelines/list/:id - List timeline (authenticated)"
  def list(conn, %{"id" => list_id} = params) do
    identity = conn.assigns.current_identity
    opts = parse_pagination_params(params)

    case Feeds.list_timeline(list_id, identity.id, opts) do
      {:ok, posts} ->
        serialized = PostSerializer.serialize_many(posts, current_identity_id: identity.id)

        # Wrap in PaginatedResponse<T> shape so the frontend's
        # `result.data` reads. Returning a bare array landed
        # `result.data = undefined` and the list page rendered
        # empty even when 20 member posts existed in DB.
        next_cursor =
          case List.last(serialized) do
            nil -> nil
            last -> last[:id] || last["id"]
          end

        conn
        |> put_link_headers(serialized, "/api/v1/timelines/list/#{list_id}")
        |> put_status(:ok)
        |> list_response(serialized, next_cursor)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "List not found"})
    end
  end

  @doc "GET /api/v1/timelines/group/:id - Group timeline (authenticated)"
  def group(conn, %{"id" => group_id} = params) do
    identity = conn.assigns.current_identity
    opts = parse_pagination_params(params)

    case Feeds.group_timeline(group_id, identity.id, opts) do
      {:ok, posts} ->
        serialized = PostSerializer.serialize_many(posts, current_identity_id: identity.id)

        conn
        |> put_link_headers(serialized, "/api/v1/timelines/group/#{group_id}")
        |> put_status(:ok)
        |> Compat.json(serialized, :statuses)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Group not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You must be a member to view this group's posts"})
    end
  end

  @doc "GET /api/v1/timelines/global - Global timeline (optional auth)"
  # Explore's Trending tab. Under "local" access an anonymous visitor may read
  # trending but not remote posts, so they get the local half of the feed.
  def trending(conn, params) do
    case check_timeline_access(conn, :local) do
      :denied ->
        deny_access(conn)

      :ok ->
        identity = conn.assigns[:current_identity]
        viewer_id = identity && identity.id
        local_only = is_nil(identity) and timeline_access() == "local"

        opts =
          parse_pagination_params(params)
          |> Keyword.merge(viewer_id: viewer_id, local_only: local_only)

        cache_key =
          "feed:trending:ser:#{viewer_id || "anon"}:#{local_only}:#{Keyword.get(opts, :limit)}"

        serialized =
          cached_feed(cache_key, first_page?(params), fn ->
            opts |> ExploreFeed.list() |> serialize_trending(viewer_id)
          end)

        conn
        |> put_link_headers(serialized, "/api/v1/timelines/trending")
        |> put_status(:ok)
        |> Compat.json(serialized, :statuses)
    end
  end

  # Adds what only this feed shows: why a post is here, and whether to offer a
  # follow button for its author.
  defp serialize_trending(rows, viewer_id) do
    posts = Enum.map(rows, &elem(&1, 0))
    authors = Map.new(posts, &{&1.id, &1.identity_id})
    reasons = Map.new(rows, fn {post, reason} -> {post.id, reason} end)

    followed =
      if viewer_id,
        do: ExploreFeed.followed_author_ids(viewer_id, Enum.uniq(Map.values(authors)))

    posts
    |> PostSerializer.serialize_many(current_identity_id: viewer_id)
    |> Enum.map(fn entry ->
      entry
      |> Map.put(:trending_reason, reasons[entry.id])
      |> Map.put(
        :viewer_follows_author,
        if(followed, do: MapSet.member?(followed, authors[entry.id]))
      )
    end)
  end

  def global(conn, params) do
    case check_timeline_access(conn, :global) do
      :denied ->
        deny_access(conn)

      :ok ->
        viewer_id =
          case conn.assigns[:current_identity] do
            nil -> nil
            identity -> identity.id
          end

        include_replies = params["include_replies"] == "true"

        opts =
          parse_pagination_params(params)
          |> Keyword.merge(include_replies: include_replies, viewer_id: viewer_id)
          |> maybe_put_public_sort(params["sort"] || params["algorithm"])

        # The prewarmed snapshot is the default newest order only — a sorted
        # request (oldest/trending) must compute fresh even on the first page.
        default_order? = Keyword.get(opts, :sort) in [nil, "newest"]

        serialized =
          cond do
            # The snapshot is shared with logged-in members, so it holds locked
            # accounts' public posts. Anonymous requests get a filtered query
            # with its own short cache instead.
            is_nil(viewer_id) ->
              cached_feed(
                "feed:global:anon:#{include_replies}:#{Keyword.get(opts, :sort, "newest")}:#{Keyword.get(opts, :limit)}",
                first_page?(params),
                fn ->
                  opts
                  |> Feeds.global_timeline()
                  |> PostSerializer.serialize_many(current_identity_id: nil)
                end
              )

            default_order? and first_page?(params) ->
              # Serve the prewarmed, viewer-independent snapshot (kept hot by
              # Feeds.PrewarmWorker) and layer this viewer's interaction
              # state on top.
              Snapshot.global_key(include_replies)
              |> Snapshot.fetch(fn ->
                [viewer_id: nil, include_replies: include_replies, include_locked: true]
                |> Feeds.global_timeline()
                |> PostSerializer.serialize_many(current_identity_id: nil)
              end)
              |> PostSerializer.apply_viewer_state(viewer_id)

            true ->
              # Older pages (cursor present) are unbounded and personalised,
              # so compute them fresh.
              opts
              |> Feeds.global_timeline()
              |> PostSerializer.serialize_many(current_identity_id: viewer_id)
          end

        conn
        |> put_link_headers(serialized, "/api/v1/timelines/global")
        |> put_status(:ok)
        |> Compat.json(serialized, :statuses)
    end
  end

  @doc "GET /api/v1/timelines/streams - Video streams timeline"
  def streams(conn, params) do
    identity = conn.assigns[:current_identity]
    viewer_id = if identity, do: identity.id, else: nil

    opts =
      params
      |> parse_pagination_params()
      |> maybe_put_streams_sort(params["sort"])
      |> maybe_put_streams_query(params["q"])
      |> maybe_put_streams_orientation(params["orientation"])
      |> maybe_put_streams_federated(params["include_federated"])

    posts = Hybridsocial.Social.Streams.streams_feed(viewer_id, opts)
    serialized = PostSerializer.serialize_many(posts, current_identity_id: viewer_id)

    conn
    |> put_link_headers(serialized, "/api/v1/timelines/streams")
    |> put_status(:ok)
    |> Compat.json(serialized, :statuses)
  end

  # Our frontend reads `result.data` off a PaginatedResponse; a Mastodon
  # client reads a bare array and takes the cursor from the Link header.
  defp list_response(conn, serialized, next_cursor) do
    if Compat.mastodon?(conn) do
      Compat.json(conn, serialized, :statuses)
    else
      json(conn, %{data: serialized, next_cursor: next_cursor, prev_cursor: nil})
    end
  end

  # ---------------------------------------------------------------------------
  # Pagination
  # ---------------------------------------------------------------------------

  defp parse_pagination_params(params) do
    opts = []

    opts =
      case params["limit"] do
        nil -> opts
        val -> Keyword.put(opts, :limit, clamp_limit(val))
      end

    opts =
      case params["max_id"] do
        nil -> opts
        val -> Keyword.put(opts, :max_id, val)
      end

    opts =
      case params["min_id"] do
        nil -> opts
        val -> Keyword.put(opts, :min_id, val)
      end

    case params["since_id"] do
      nil -> opts
      val -> Keyword.put(opts, :since_id, val)
    end
  end

  # Only accept the known ordering keywords; anything else falls through to
  # the feed's default (trending) rather than being trusted as a raw value.
  @streams_sorts ~w(trending newest oldest)
  defp maybe_put_streams_sort(opts, sort) when sort in @streams_sorts,
    do: Keyword.put(opts, :sort, sort)

  defp maybe_put_streams_sort(opts, _), do: opts

  # Clips of every size are the default; only the explicit "portrait" narrows
  # the feed to vertical-only, so a caller that omits the param never gets a
  # silently partial feed.
  defp maybe_put_streams_orientation(opts, "portrait"),
    do: Keyword.put(opts, :orientation, :portrait)

  defp maybe_put_streams_orientation(opts, _), do: opts

  # Explore's Local/Global sort control: "trending" (engagement-ranked),
  # "newest" (default chronological), or "oldest" (ascending). `Feeds`
  # dispatches on `:sort`. `?algorithm=trending` is accepted as a legacy alias
  # for `?sort=trending` (the standalone Trending tab). Unknown values fall
  # through to the default order.
  @public_sorts ~w(trending newest oldest)
  defp maybe_put_public_sort(opts, sort) when sort in @public_sorts,
    do: Keyword.put(opts, :sort, sort)

  defp maybe_put_public_sort(opts, _), do: opts

  # Per-user opt-in: `include_federated=true` surfaces every public fediverse
  # video for this viewer. Only the literal "true" opts in.
  defp maybe_put_streams_federated(opts, "true"),
    do: Keyword.put(opts, :include_federated, true)

  defp maybe_put_streams_federated(opts, _), do: opts

  defp maybe_put_streams_query(opts, q) when is_binary(q) and q != "",
    do: Keyword.put(opts, :q, q)

  defp maybe_put_streams_query(opts, _), do: opts

  # Cache the serialized first page of a feed for @feed_cache_ttl seconds.
  # `compute_fun` produces the JSON-ready payload on a miss; anything but
  # the first page (a cursor is present) is never cached.
  defp cached_feed(cache_key, cacheable?, compute_fun) do
    if cacheable? do
      case safe_cache_get(cache_key) do
        nil ->
          serialized = compute_fun.()
          safe_cache_set(cache_key, serialized)
          serialized

        cached ->
          cached
      end
    else
      compute_fun.()
    end
  end

  defp safe_cache_get(key) do
    Cache.get(key)
  rescue
    _ -> nil
  end

  defp safe_cache_set(key, value) do
    Cache.set(key, value, @feed_cache_ttl)
  rescue
    _ -> :ok
  end

  defp first_page?(params) do
    is_nil(params["max_id"]) and is_nil(params["min_id"]) and is_nil(params["since_id"])
  end

  defp put_link_headers(conn, posts, base_path) do
    case posts do
      [] ->
        conn

      posts ->
        # Cached payloads round-trip through JSON, so entries can have
        # string keys ("id") while fresh ones have atom keys (:id).
        first = entry_id(List.first(posts))
        last = entry_id(List.last(posts))

        links = [
          "<#{base_path}?max_id=#{last}>; rel=\"next\"",
          "<#{base_path}?min_id=#{first}>; rel=\"prev\""
        ]

        put_resp_header(conn, "link", Enum.join(links, ", "))
    end
  end

  defp entry_id(entry) when is_map(entry), do: entry[:id] || entry["id"]
  defp entry_id(_), do: nil

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  defp serialize_timeline_entries(entries, identity_id) do
    Enum.map(entries, fn
      %{type: :post, data: post} ->
        PostSerializer.serialize(post, current_identity_id: identity_id)

      %{type: :boost, data: boost} ->
        %{
          id: boost.id,
          type: "boost",
          created_at: boost.inserted_at,
          account:
            PostSerializer.serialize_account(
              boost.identity,
              Hybridsocial.Badges.instance_badges(boost.identity)
            ),
          post: PostSerializer.serialize(boost.post, current_identity_id: identity_id)
        }
    end)
  end
end

defmodule HybridsocialWeb.Api.V1.TimelineController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Feeds
  alias Hybridsocial.Config
  alias HybridsocialWeb.Serializers.PostSerializer
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

  # Timeline access levels:
  # "none"      — disallow all, require login
  # "local"     — allow local + trending, block global
  # "all"       — allow everything
  defp timeline_access do
    Config.get("public_timeline_access", "all")
  end

  defp check_timeline_access(conn, level) do
    has_user = conn.assigns[:current_identity] != nil
    access = timeline_access()

    cond do
      has_user -> :ok
      access == "none" -> :denied
      access == "local" and level == :global -> :denied
      true -> :ok
    end
  end

  defp deny_access(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "timeline.login_required", message: "You need to create an account to view this timeline."})
    |> halt()
  end

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

    entries = Feeds.home_timeline(identity.id, opts)

    identity_id = identity.id

    posts =
      if Keyword.get(opts, :algorithm) do
        PostSerializer.serialize_many(entries, current_identity_id: identity_id)
      else
        serialize_timeline_entries(entries, identity_id)
      end

    conn
    |> put_link_headers(posts, "/api/v1/timelines/home")
    |> put_status(:ok)
    |> json(posts)
  end

  @doc "GET /api/v1/timelines/public - Public timeline (optional auth)"
  def public(conn, params) do
    case check_timeline_access(conn, :local) do
      :denied -> deny_access(conn)
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

    posts = Feeds.public_timeline(opts)
    serialized = PostSerializer.serialize_many(posts, current_identity_id: viewer_id)

    conn
    |> put_link_headers(serialized, "/api/v1/timelines/public")
    |> put_status(:ok)
    |> json(serialized)

    end
  end

  @doc "GET /api/v1/timelines/tag/:hashtag - Hashtag timeline (optional auth)"
  def hashtag(conn, %{"hashtag" => hashtag} = params) do
    case check_timeline_access(conn, :local) do
      :denied -> deny_access(conn)
      :ok ->

    viewer_id =
      case conn.assigns[:current_identity] do
        nil -> nil
        identity -> identity.id
      end

    opts =
      parse_pagination_params(params)
      |> Keyword.put(:viewer_id, viewer_id)

    posts = Feeds.hashtag_timeline(hashtag, opts)
    serialized = PostSerializer.serialize_many(posts, current_identity_id: viewer_id)

    conn
    |> put_link_headers(serialized, "/api/v1/timelines/tag/#{hashtag}")
    |> put_status(:ok)
    |> json(serialized)

    end
  end

  @doc "GET /api/v1/timelines/list/:id - List timeline (authenticated)"
  def list(conn, %{"id" => list_id} = params) do
    identity = conn.assigns.current_identity
    opts = parse_pagination_params(params)

    case Feeds.list_timeline(list_id, identity.id, opts) do
      {:ok, posts} ->
        serialized = PostSerializer.serialize_many(posts, current_identity_id: identity.id)

        conn
        |> put_link_headers(serialized, "/api/v1/timelines/list/#{list_id}")
        |> put_status(:ok)
        |> json(serialized)

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
        |> json(serialized)

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
  def global(conn, params) do
    case check_timeline_access(conn, :global) do
      :denied -> deny_access(conn)
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
        viewer_id: viewer_id
      )

    posts = Feeds.global_timeline(opts)
    serialized = PostSerializer.serialize_many(posts, current_identity_id: viewer_id)

    conn
    |> put_link_headers(serialized, "/api/v1/timelines/global")
    |> put_status(:ok)
    |> json(serialized)

    end
  end

  @doc "GET /api/v1/timelines/streams - Video streams (reels) timeline"
  def streams(conn, params) do
    identity = conn.assigns[:current_identity]
    viewer_id = if identity, do: identity.id, else: nil
    opts = parse_pagination_params(params)

    posts = Hybridsocial.Social.Streams.streams_feed(viewer_id, opts)
    serialized = PostSerializer.serialize_many(posts, current_identity_id: viewer_id)

    conn
    |> put_link_headers(serialized, "/api/v1/timelines/streams")
    |> put_status(:ok)
    |> json(serialized)
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

  defp put_link_headers(conn, posts, base_path) do
    case posts do
      [] ->
        conn

      posts ->
        first = List.first(posts)
        last = List.last(posts)

        links = [
          "<#{base_path}?max_id=#{last[:id]}>; rel=\"next\"",
          "<#{base_path}?min_id=#{first[:id]}>; rel=\"prev\""
        ]

        put_resp_header(conn, "link", Enum.join(links, ", "))
    end
  end

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

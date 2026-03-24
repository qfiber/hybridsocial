defmodule HybridsocialWeb.Api.V1.TimelineController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Feeds
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

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

    posts =
      if Keyword.get(opts, :algorithm) do
        Enum.map(entries, &serialize_post/1)
      else
        serialize_timeline_entries(entries)
      end

    conn
    |> put_link_headers(posts, "/api/v1/timelines/home")
    |> put_status(:ok)
    |> json(posts)
  end

  @doc "GET /api/v1/timelines/public - Public timeline (optional auth)"
  def public(conn, params) do
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
    serialized = Enum.map(posts, &serialize_post/1)

    conn
    |> put_link_headers(serialized, "/api/v1/timelines/public")
    |> put_status(:ok)
    |> json(serialized)
  end

  @doc "GET /api/v1/timelines/tag/:hashtag - Hashtag timeline (optional auth)"
  def hashtag(conn, %{"hashtag" => hashtag} = params) do
    viewer_id =
      case conn.assigns[:current_identity] do
        nil -> nil
        identity -> identity.id
      end

    opts =
      parse_pagination_params(params)
      |> Keyword.put(:viewer_id, viewer_id)

    posts = Feeds.hashtag_timeline(hashtag, opts)
    serialized = Enum.map(posts, &serialize_post/1)

    conn
    |> put_link_headers(serialized, "/api/v1/timelines/tag/#{hashtag}")
    |> put_status(:ok)
    |> json(serialized)
  end

  @doc "GET /api/v1/timelines/list/:id - List timeline (authenticated)"
  def list(conn, %{"id" => list_id} = params) do
    identity = conn.assigns.current_identity
    opts = parse_pagination_params(params)

    case Feeds.list_timeline(list_id, identity.id, opts) do
      {:ok, posts} ->
        serialized = Enum.map(posts, &serialize_post/1)

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
        serialized = Enum.map(posts, &serialize_post/1)

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
    serialized = Enum.map(posts, &serialize_post/1)

    conn
    |> put_link_headers(serialized, "/api/v1/timelines/global")
    |> put_status(:ok)
    |> json(serialized)
  end

  @doc "GET /api/v1/timelines/streams - Video streams (reels) timeline"
  def streams(conn, params) do
    identity = conn.assigns[:current_identity]
    viewer_id = if identity, do: identity.id, else: nil
    opts = parse_pagination_params(params)

    posts = Hybridsocial.Social.Streams.streams_feed(viewer_id, opts)
    serialized = Enum.map(posts, &serialize_post/1)

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

  defp serialize_timeline_entries(entries) do
    Enum.map(entries, fn
      %{type: :post, data: post} ->
        serialize_post(post)

      %{type: :boost, data: boost} ->
        %{
          id: boost.id,
          type: "boost",
          created_at: boost.inserted_at,
          account:
            serialize_account(boost.identity, Hybridsocial.Badges.instance_badges(boost.identity)),
          post: serialize_post(boost.post)
        }
    end)
  end

  defp serialize_post(post) do
    badges =
      Hybridsocial.Badges.badges_for_post(
        post.identity,
        group_id: post.group_id,
        page_id: post.page_id
      )

    # If the identity has force_sensitive enabled, override sensitive to true
    sensitive =
      case post.identity do
        %{force_sensitive: true} -> true
        _ -> post.sensitive
      end

    %{
      id: post.id,
      content: post.content,
      content_html: post.content_html,
      visibility: post.visibility,
      sensitive: sensitive,
      spoiler_text: post.spoiler_text,
      reply_count: post.reply_count,
      boost_count: post.boost_count,
      reaction_count: post.reaction_count,
      is_pinned: post.is_pinned,
      created_at: post.inserted_at,
      edited_at: post.edited_at,
      parent_id: post.parent_id,
      account: serialize_account(post.identity, badges)
    }
  end

  defp serialize_account(nil, _badges), do: nil

  defp serialize_account(identity, badges) do
    %{
      id: identity.id,
      handle: identity.handle,
      display_name: identity.display_name,
      avatar_url: identity.avatar_url,
      header_url: identity.header_url,
      bio: identity.bio,
      is_bot: identity.is_bot,
      is_locked: identity.is_locked,
      badges: badges,
      created_at: identity.inserted_at
    }
  end
end

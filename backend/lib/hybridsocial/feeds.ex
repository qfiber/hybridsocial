defmodule Hybridsocial.Feeds do
  @moduledoc """
  The Feeds context. Provides timeline/feed queries with cursor-based pagination,
  visibility enforcement, and block/mute filtering.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Post, Follow, Block, Boost, List, ListMember}
  alias Hybridsocial.Feeds.Visibility
  alias Hybridsocial.Cache.FeedCache

  @default_limit 20
  @max_limit 40

  # ---------------------------------------------------------------------------
  # Home Timeline
  # ---------------------------------------------------------------------------

  @doc """
  Returns the home timeline for the given identity: posts from accounts the user
  follows (accepted follows) plus boosts from followed accounts, in reverse
  chronological order with cursor-based pagination.

  Excludes soft-deleted posts and posts from blocked/muted accounts.

  ## Options
    * `:limit`  - max number of posts to return (default 20, max 40)
    * `:max_id` - return posts with id less than this value (older)
    * `:min_id` - return posts with id greater than this value (newer)
    * `:since_id` - return posts with id greater than this value (newest first)
  """
  def home_timeline(identity_id, opts \\ []) do
    if Keyword.get(opts, :algorithm, false) do
      Hybridsocial.Feeds.Algorithm.algorithmic_timeline(identity_id, opts)
    else
      if cacheable?(opts) do
        case safe_cache_get(fn -> FeedCache.get_home_timeline(identity_id) end) do
          nil ->
            result = fetch_home_timeline(identity_id, opts)
            safe_cache_set(fn -> FeedCache.set_home_timeline(identity_id, result) end)
            result

          cached ->
            cached
        end
      else
        fetch_home_timeline(identity_id, opts)
      end
    end
  end

  defp fetch_home_timeline(identity_id, opts) do
    limit = parse_limit(opts)

    # Subquery: IDs of accounts the viewer follows
    followed_ids =
      Follow
      |> where([f], f.follower_id == ^identity_id and f.status == :accepted)
      |> select([f], f.followee_id)

    # Original posts from followed accounts + own posts
    posts_query =
      Post
      |> where([p], p.identity_id in subquery(followed_ids) or p.identity_id == ^identity_id)
      |> where([p], is_nil(p.deleted_at))
      |> apply_cursor_filters(opts)
      |> Visibility.apply_block_filter(identity_id)
      |> Visibility.apply_mute_filter(identity_id)
      |> order_by([p], desc: p.inserted_at)
      |> limit(^limit)
      |> preload(:identity)
      |> Repo.all()

    # Boosts from followed accounts
    boosts =
      Boost
      |> where([b], b.identity_id in subquery(followed_ids) or b.identity_id == ^identity_id)
      |> where([b], is_nil(b.deleted_at))
      |> join(:inner, [b], p in Post, on: b.post_id == p.id and is_nil(p.deleted_at))
      |> apply_boost_cursor_filters(opts)
      |> order_by([b], desc: b.inserted_at)
      |> limit(^limit)
      |> preload([b, p], post: {p, :identity})
      |> preload(:identity)
      |> Repo.all()

    # Merge posts and boosts, sort by inserted_at descending, take limit
    merge_timeline_entries(posts_query, boosts)
    |> Enum.take(limit)
  end

  # ---------------------------------------------------------------------------
  # Public Timeline
  # ---------------------------------------------------------------------------

  @doc """
  Returns the public timeline: all local public posts in reverse chronological
  order with cursor-based pagination.

  Excludes soft-deleted posts and replies (unless `include_replies: true`).

  ## Options
    * `:limit`           - max number of posts (default 20, max 40)
    * `:max_id`          - return posts older than this id
    * `:min_id`          - return posts newer than this id
    * `:since_id`        - return posts newer than this id
    * `:include_replies` - include replies (default false)
    * `:local_only`      - only local posts (default true, reserved for federation)
  """
  def public_timeline(opts \\ []) do
    if cacheable?(opts) do
      case safe_cache_get(fn -> FeedCache.get_public_timeline() end) do
        nil ->
          result = fetch_public_timeline(opts)
          safe_cache_set(fn -> FeedCache.set_public_timeline(result) end)
          result

        cached ->
          cached
      end
    else
      fetch_public_timeline(opts)
    end
  end

  defp fetch_public_timeline(opts) do
    limit = parse_limit(opts)
    include_replies = Keyword.get(opts, :include_replies, false)

    query =
      Post
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.deleted_at))
      |> maybe_exclude_replies(include_replies)
      |> apply_cursor_filters(opts)
      |> order_by([p], desc: p.inserted_at)
      |> limit(^limit)
      |> preload(:identity)

    Repo.all(query)
  end

  # ---------------------------------------------------------------------------
  # Account Timeline
  # ---------------------------------------------------------------------------

  @doc """
  Returns the timeline for a specific account. Visibility depends on the
  relationship between the account and the viewer.

  - If the viewer is the account owner: show all own posts
  - If the viewer follows the account: show public + followers-only posts
  - Otherwise: show public posts only
  - If the viewer is blocked by the account: return empty list

  ## Options
    * `:limit`           - max number of posts (default 20, max 40)
    * `:max_id`          - return posts older than this id
    * `:min_id`          - return posts newer than this id
    * `:since_id`        - return posts newer than this id
    * `:exclude_replies` - exclude replies (default false)
    * `:exclude_boosts`  - exclude boosts (default false)
    * `:only_media`      - only posts with media type (default false)
    * `:pinned`          - only pinned posts (default false)
  """
  def account_timeline(identity_id, viewer_id \\ nil, opts \\ []) do
    # If the viewer is blocked by this account, return nothing
    if viewer_id && blocked_by?(identity_id, viewer_id) do
      []
    else
      limit = parse_limit(opts)
      exclude_replies = Keyword.get(opts, :exclude_replies, false)
      only_media = Keyword.get(opts, :only_media, false)
      pinned = Keyword.get(opts, :pinned, false)

      query =
        Post
        |> where([p], p.identity_id == ^identity_id)
        |> where([p], is_nil(p.deleted_at))
        |> apply_account_visibility(identity_id, viewer_id)
        |> maybe_exclude_replies(not exclude_replies)
        |> maybe_only_media(only_media)
        |> maybe_only_pinned(pinned)
        |> apply_cursor_filters(opts)
        |> order_by([p], desc: p.inserted_at)
        |> limit(^limit)
        |> preload(:identity)

      posts = Repo.all(query)

      exclude_boosts = Keyword.get(opts, :exclude_boosts, false)

      if exclude_boosts do
        posts
      else
        # Also include boosts by this identity
        boosts =
          Boost
          |> where([b], b.identity_id == ^identity_id)
          |> where([b], is_nil(b.deleted_at))
          |> join(:inner, [b], p in Post, on: b.post_id == p.id and is_nil(p.deleted_at))
          |> apply_boost_cursor_filters(opts)
          |> order_by([b], desc: b.inserted_at)
          |> limit(^limit)
          |> preload([b, p], post: {p, :identity})
          |> preload(:identity)
          |> Repo.all()

        merge_timeline_entries(posts, boosts)
        |> Enum.take(limit)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Hashtag Timeline
  # ---------------------------------------------------------------------------

  @doc """
  Returns public posts containing a specific hashtag in reverse chronological
  order with cursor-based pagination.

  Only public, non-deleted posts are included.

  ## Options
    * `:limit`    - max number of posts (default 20, max 40)
    * `:max_id`   - return posts older than this id
    * `:min_id`   - return posts newer than this id
    * `:since_id` - return posts newer than this id
  """
  def hashtag_timeline(hashtag, opts \\ []) do
    limit = parse_limit(opts)
    tag_pattern = "%##{hashtag}%"

    query =
      Post
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.deleted_at))
      |> where([p], ilike(p.content, ^tag_pattern))
      |> apply_cursor_filters(opts)
      |> order_by([p], desc: p.inserted_at)
      |> limit(^limit)
      |> preload(:identity)

    Repo.all(query)
  end

  # ---------------------------------------------------------------------------
  # List Timeline
  # ---------------------------------------------------------------------------

  @doc """
  Returns the list timeline: posts from accounts in the specified list.
  The viewer must own the list.

  ## Options
    * `:limit`           - max number of posts (default 20, max 40)
    * `:max_id`          - return posts older than this id
    * `:min_id`          - return posts newer than this id
    * `:since_id`        - return posts newer than this id
  """
  def list_timeline(list_id, viewer_id, opts \\ []) do
    # Verify the viewer owns the list
    list =
      List
      |> where([l], l.id == ^list_id and l.identity_id == ^viewer_id)
      |> Repo.one()

    case list do
      nil ->
        {:error, :not_found}

      _list ->
        limit = parse_limit(opts)

        member_ids =
          ListMember
          |> where([lm], lm.list_id == ^list_id)
          |> select([lm], lm.target_identity_id)

        query =
          Post
          |> where([p], p.identity_id in subquery(member_ids))
          |> where([p], is_nil(p.deleted_at))
          |> apply_cursor_filters(opts)
          |> Visibility.apply_block_filter(viewer_id)
          |> Visibility.apply_mute_filter(viewer_id)
          |> order_by([p], desc: p.inserted_at)
          |> limit(^limit)
          |> preload(:identity)

        {:ok, Repo.all(query)}
    end
  end

  # ---------------------------------------------------------------------------
  # Global Timeline
  # ---------------------------------------------------------------------------

  @doc """
  Returns the global timeline: all public posts (local + federated) in reverse
  chronological order with cursor-based pagination.

  This is similar to the public timeline but without the `local_only` restriction.
  Federated posts will appear here once federation is working.

  ## Options
    * `:limit`           - max number of posts (default 20, max 40)
    * `:max_id`          - return posts older than this id
    * `:min_id`          - return posts newer than this id
    * `:since_id`        - return posts newer than this id
    * `:include_replies` - include replies (default false)
  """
  def global_timeline(opts \\ []) do
    limit = parse_limit(opts)
    include_replies = Keyword.get(opts, :include_replies, false)

    query =
      Post
      |> where([p], p.visibility == "public")
      |> where([p], is_nil(p.deleted_at))
      |> maybe_exclude_replies(include_replies)
      |> apply_cursor_filters(opts)
      |> order_by([p], desc: p.inserted_at)
      |> limit(^limit)
      |> preload(:identity)

    Repo.all(query)
  end

  # ---------------------------------------------------------------------------
  # Group Timeline
  # ---------------------------------------------------------------------------

  @doc """
  Returns the group timeline: posts with the given group_id in reverse
  chronological order with cursor-based pagination.

  For private groups, verifies that the viewer is an approved member.
  Public groups show all posts to everyone.

  ## Options
    * `:limit`    - max number of posts (default 20, max 40)
    * `:max_id`   - return posts older than this id
    * `:min_id`   - return posts newer than this id
    * `:since_id` - return posts newer than this id
  """
  def group_timeline(group_id, viewer_id, opts \\ []) do
    case Hybridsocial.Groups.get_group(group_id) do
      nil ->
        {:error, :not_found}

      group ->
        if group.visibility != :public && !Hybridsocial.Groups.member?(group_id, viewer_id) do
          {:error, :forbidden}
        else
          limit = parse_limit(opts)

          query =
            Post
            |> where([p], p.group_id == ^group_id)
            |> where([p], is_nil(p.deleted_at))
            |> apply_cursor_filters(opts)
            |> order_by([p], desc: p.inserted_at)
            |> limit(^limit)
            |> preload(:identity)

          {:ok, Repo.all(query)}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp apply_cursor_filters(query, opts) do
    query
    |> maybe_max_id(Keyword.get(opts, :max_id))
    |> maybe_min_id(Keyword.get(opts, :min_id))
    |> maybe_since_id(Keyword.get(opts, :since_id))
  end

  defp maybe_max_id(query, nil), do: query
  defp maybe_max_id(query, max_id), do: where(query, [p], p.id < ^max_id)

  defp maybe_min_id(query, nil), do: query
  defp maybe_min_id(query, min_id), do: where(query, [p], p.id > ^min_id)

  defp maybe_since_id(query, nil), do: query
  defp maybe_since_id(query, since_id), do: where(query, [p], p.id > ^since_id)

  defp apply_boost_cursor_filters(query, opts) do
    query
    |> maybe_boost_max_id(Keyword.get(opts, :max_id))
    |> maybe_boost_min_id(Keyword.get(opts, :min_id))
  end

  defp maybe_boost_max_id(query, nil), do: query
  defp maybe_boost_max_id(query, max_id), do: where(query, [b], b.id < ^max_id)

  defp maybe_boost_min_id(query, nil), do: query
  defp maybe_boost_min_id(query, min_id), do: where(query, [b], b.id > ^min_id)

  defp maybe_exclude_replies(query, true = _include), do: query

  defp maybe_exclude_replies(query, false = _include) do
    where(query, [p], is_nil(p.parent_id))
  end

  defp maybe_only_media(query, false), do: query
  defp maybe_only_media(query, true), do: where(query, [p], p.post_type == "media")

  defp maybe_only_pinned(query, false), do: query
  defp maybe_only_pinned(query, true), do: where(query, [p], p.is_pinned == true)

  defp apply_account_visibility(query, identity_id, viewer_id)
       when identity_id == viewer_id and not is_nil(viewer_id) do
    # Owner sees everything
    query
  end

  defp apply_account_visibility(query, identity_id, viewer_id) when not is_nil(viewer_id) do
    # Check if viewer follows the account
    follows? =
      Follow
      |> where([f],
        f.follower_id == ^viewer_id and
          f.followee_id == ^identity_id and
          f.status == :accepted
      )
      |> Repo.exists?()

    if follows? do
      where(query, [p], p.visibility in ["public", "followers"])
    else
      where(query, [p], p.visibility == "public")
    end
  end

  defp apply_account_visibility(query, _identity_id, nil) do
    where(query, [p], p.visibility == "public")
  end

  defp blocked_by?(account_id, viewer_id) do
    Block
    |> where([b], b.blocker_id == ^account_id and b.blocked_id == ^viewer_id)
    |> Repo.exists?()
  end

  # Cache is only used for first-page loads (no cursor params).
  defp cacheable?(opts) do
    is_nil(Keyword.get(opts, :max_id)) and
      is_nil(Keyword.get(opts, :min_id)) and
      is_nil(Keyword.get(opts, :since_id))
  end

  defp safe_cache_get(fun) do
    try do
      fun.()
    rescue
      _ -> nil
    end
  end

  defp safe_cache_set(fun) do
    try do
      fun.()
    rescue
      _ -> :ok
    end
  end

  @doc false
  def merge_timeline_entries(posts, boosts) do
    post_entries = Enum.map(posts, fn p -> %{type: :post, data: p, timestamp: p.inserted_at} end)

    boost_entries =
      Enum.map(boosts, fn b -> %{type: :boost, data: b, timestamp: b.inserted_at} end)

    (post_entries ++ boost_entries)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end
end

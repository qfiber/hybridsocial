defmodule Hybridsocial.Social.Posts do
  @moduledoc """
  Context module for managing posts, reactions, boosts, and hashtags.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Post, PostRevision, Reaction, Boost, Hashtag, Polls}
  alias Hybridsocial.Premium.TierLimits
  alias Hybridsocial.Content.Emojis

  @default_page_size 20

  # --- Post CRUD ---

  def create_post(identity_id, attrs, identity \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    # Resolve tier limits
    limits =
      if identity do
        TierLimits.limits_for(identity)
      else
        TierLimits.limits_for_tier("verified_pro")
      end

    edit_window = limits[:edit_window] || 900

    edit_expires_at =
      if edit_window == 0 do
        # Unlimited editing
        nil
      else
        DateTime.add(now, edit_window, :second)
        |> DateTime.truncate(:microsecond)
      end

    # Generate HTML from markdown content
    content_html =
      case attrs["content"] do
        nil -> nil
        content -> Hybridsocial.Content.Sanitizer.sanitize_post_content(content)
      end

    post_attrs =
      attrs
      |> Map.put("identity_id", identity_id)
      |> Map.put("published_at", now)
      |> Map.put("content_html", content_html)
      |> maybe_resolve_root_id()

    changeset =
      %Post{}
      |> Post.create_changeset(post_attrs, char_limit: limits[:char_limit] || 5000)
      |> Ecto.Changeset.put_change(:published_at, now)

    changeset =
      if edit_expires_at do
        Ecto.Changeset.put_change(changeset, :edit_expires_at, edit_expires_at)
      else
        changeset
      end

    with :ok <- validate_premium_emojis(attrs["content"], identity) do
      insert_post(changeset, attrs)
    end
  end

  defp validate_premium_emojis(nil, _identity), do: :ok
  defp validate_premium_emojis(_content, nil), do: :ok

  defp validate_premium_emojis(content, identity) do
    case Emojis.validate_premium_emoji_access(content, identity) do
      :ok -> :ok
      {:error, shortcodes} -> {:error, :premium_emojis_required, shortcodes}
    end
  end

  defp insert_post(changeset, attrs) do
    case Repo.insert(changeset) do
      {:ok, post} ->
        if post.content, do: extract_and_link_hashtags(post)

        if post.post_type == "poll" do
          poll_attrs = Map.take(attrs, ["options", "multiple_choice", "expires_at"])
          Polls.create_poll(post.id, poll_attrs)
        end

        # Increment parent's reply count
        if post.parent_id do
          Post
          |> where([p], p.id == ^post.parent_id)
          |> Repo.update_all(inc: [reply_count: 1])
        end

        post = Repo.preload(post, poll: :options)

        # Broadcast for OpenSearch indexing
        Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "posts", {:post_created, post})

        {:ok, post}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Resolves root_id from parent chain. If the post has a parent_id but no root_id,
  walks up the parent chain to find the root post.
  """
  def maybe_resolve_root_id(%{"parent_id" => parent_id} = attrs)
      when is_binary(parent_id) and parent_id != "" do
    if Map.get(attrs, "root_id") do
      attrs
    else
      case Repo.get(Post, parent_id) do
        nil ->
          attrs

        parent ->
          root_id = parent.root_id || parent.id
          Map.put(attrs, "root_id", root_id)
      end
    end
  end

  def maybe_resolve_root_id(attrs), do: attrs

  def edit_post(post_id, identity_id, attrs, identity \\ nil) do
    with {:ok, post} <- get_owned_post(post_id, identity_id),
         :ok <- validate_premium_emojis(attrs["content"], identity) do
      limits =
        if identity do
          TierLimits.limits_for(identity)
        else
          TierLimits.limits_for_tier("verified_pro")
        end

      revision_number = get_next_revision_number(post_id)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:revision, fn _ ->
        %PostRevision{}
        |> PostRevision.changeset(%{
          post_id: post.id,
          content: post.content,
          content_html: post.content_html,
          edited_at: post.edited_at || post.inserted_at,
          revision_number: revision_number
        })
      end)
      |> Ecto.Multi.update(:post, fn _ ->
        Post.edit_changeset(post, attrs, char_limit: limits[:char_limit] || 5000)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{post: post}} ->
          if post.content, do: extract_and_link_hashtags(post)
          Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "posts", {:post_updated, post})
          {:ok, post}

        {:error, :post, changeset, _} ->
          {:error, changeset}

        {:error, :revision, changeset, _} ->
          {:error, changeset}
      end
    end
  end

  def delete_post(post_id, identity_id) do
    with {:ok, post} <- get_owned_post(post_id, identity_id) do
      case post |> Post.soft_delete_changeset() |> Repo.update() do
        {:ok, deleted} ->
          Phoenix.PubSub.broadcast(Hybridsocial.PubSub, "posts", {:post_deleted, post_id})
          {:ok, deleted}

        error ->
          error
      end
    end
  end

  # --- Post queries ---

  def get_post(id) do
    Post
    |> where([p], is_nil(p.deleted_at))
    |> Repo.get(id)
  end

  def get_post!(id) do
    Post
    |> where([p], is_nil(p.deleted_at))
    |> Repo.get!(id)
  end

  def get_post_with_context(id) do
    Post
    |> where([p], is_nil(p.deleted_at))
    |> Repo.get(id)
    |> case do
      nil -> nil
      post -> Repo.preload(post, [:identity, :parent, :quote, poll: :options])
    end
  end

  def get_thread(post_id) do
    case get_post(post_id) do
      nil ->
        {:error, :not_found}

      post ->
        # Walk up the parent chain to get true ancestors
        ancestors = collect_ancestors(post, [])

        # Descendants: direct replies to this post, and their children
        descendants =
          Post
          |> where([p], is_nil(p.deleted_at))
          |> where([p], p.parent_id == ^post_id or p.root_id == ^post_id)
          |> where([p], p.id != ^post.id)
          |> order_by([p], asc: p.published_at)
          |> Repo.all()
          |> Repo.preload(:identity)

        {:ok, %{ancestors: ancestors, descendants: descendants}}
    end
  end

  # Walk up parent chain to collect true ancestors (max 20 to prevent loops)
  # Includes soft-deleted posts so they render as tombstones
  defp collect_ancestors(%{parent_id: nil}, acc), do: Enum.reverse(acc)
  defp collect_ancestors(_, acc) when length(acc) >= 20, do: Enum.reverse(acc)

  defp collect_ancestors(%{parent_id: parent_id}, acc) when is_binary(parent_id) do
    case Repo.get(Post, parent_id) do
      nil ->
        Enum.reverse(acc)

      parent ->
        parent = Repo.preload(parent, :identity)
        collect_ancestors(parent, [parent | acc])
    end
  end

  defp collect_ancestors(_, acc), do: Enum.reverse(acc)

  def get_revisions(post_id) do
    PostRevision
    |> where([r], r.post_id == ^post_id)
    |> order_by([r], asc: r.revision_number)
    |> Repo.all()
  end

  # --- Reactions ---

  def react(post_id, identity_id, type, opts \\ []) do
    with {:ok, _post} <- get_existing_post(post_id) do
      case get_existing_reaction(post_id, identity_id) do
        nil ->
          %Reaction{}
          |> Reaction.changeset(%{post_id: post_id, identity_id: identity_id, type: type}, opts)
          |> Repo.insert()
          |> case do
            {:ok, reaction} ->
              update_reaction_count(post_id, 1)
              {:ok, reaction}

            error ->
              error
          end

        existing ->
          existing
          |> Reaction.changeset(%{type: type}, opts)
          |> Repo.update()
      end
    end
  end

  def unreact(post_id, identity_id) do
    case get_existing_reaction(post_id, identity_id) do
      nil ->
        {:error, :not_found}

      reaction ->
        case Repo.delete(reaction) do
          {:ok, reaction} ->
            update_reaction_count(post_id, -1)
            {:ok, reaction}

          error ->
            error
        end
    end
  end

  def get_reactions(post_id) do
    Reaction
    |> where([r], r.post_id == ^post_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
    |> Repo.preload(:identity)
  end

  # --- Boosts ---

  def boost(post_id, identity_id) do
    with {:ok, _post} <- get_existing_post(post_id) do
      %Boost{}
      |> Boost.changeset(%{post_id: post_id, identity_id: identity_id})
      |> Repo.insert()
      |> case do
        {:ok, boost} ->
          update_boost_count(post_id, 1)
          {:ok, boost}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def unboost(post_id, identity_id) do
    case get_existing_boost(post_id, identity_id) do
      nil ->
        {:error, :not_found}

      boost ->
        case Repo.delete(boost) do
          {:ok, boost} ->
            update_boost_count(post_id, -1)
            {:ok, boost}

          error ->
            error
        end
    end
  end

  # --- Quote posts ---

  def quote_post(identity_id, quoted_post_id, attrs) do
    with {:ok, _quoted} <- get_existing_post(quoted_post_id) do
      attrs
      |> Map.put("quote_id", quoted_post_id)
      |> then(&create_post(identity_id, &1))
    end
  end

  # --- Pin/Unpin ---

  def reacted_posts(identity_id, opts \\ []) do
    max_id = Keyword.get(opts, :max_id)

    # Get post IDs from reactions, ordered by reaction time
    reaction_query =
      Reaction
      |> where([r], r.identity_id == ^identity_id)
      |> order_by([r], desc: r.inserted_at)
      |> select([r], r.post_id)
      |> limit(20)

    reaction_query = if max_id, do: where(reaction_query, [r], r.id < ^max_id), else: reaction_query

    post_ids = Repo.all(reaction_query)

    Post
    |> where([p], p.id in ^post_ids and is_nil(p.deleted_at))
    |> preload([:identity, :quote])
    |> Repo.all()
    |> Enum.sort_by(fn p -> Enum.find_index(post_ids, &(&1 == p.id)) end)
  end

  def pinned_count(identity_id) do
    Post
    |> where([p], p.identity_id == ^identity_id and p.is_pinned == true and is_nil(p.deleted_at))
    |> Repo.aggregate(:count)
  end

  def pin_post(post_id, identity_id) do
    with {:ok, post} <- get_owned_post(post_id, identity_id) do
      post
      |> Ecto.Changeset.change(is_pinned: true)
      |> Repo.update()
    end
  end

  def unpin_post(post_id, identity_id) do
    with {:ok, post} <- get_owned_post(post_id, identity_id) do
      post
      |> Ecto.Changeset.change(is_pinned: false)
      |> Repo.update()
    end
  end

  # --- Hashtags ---

  def extract_hashtags(content) when is_binary(content) do
    ~r/#([a-zA-Z0-9_]+)/
    |> Regex.scan(content)
    |> Enum.map(fn [_, tag] -> String.downcase(tag) end)
    |> Enum.uniq()
  end

  def extract_hashtags(_), do: []

  # --- Identity posts ---

  def posts_by_identity(identity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_page_size)
    max_id = Keyword.get(opts, :max_id)
    exclude_replies = Keyword.get(opts, :exclude_replies, false)
    only_media = Keyword.get(opts, :only_media, false)
    only_direct = Keyword.get(opts, :only_direct, false)

    query =
      Post
      |> where([p], p.identity_id == ^identity_id)
      |> where([p], is_nil(p.deleted_at))
      |> order_by([p], desc: p.published_at)
      |> limit(^limit)

    query = if max_id, do: where(query, [p], p.id < ^max_id), else: query
    query = if exclude_replies, do: where(query, [p], is_nil(p.parent_id)), else: query
    query = if only_direct, do: where(query, [p], p.visibility == "direct"), else: query

    query = if only_media, do: where(query, [p], p.post_type == "media"), else: query

    Repo.all(query) |> Repo.preload([:identity, :quote])
  end

  # --- Admin operations ---

  @doc """
  Retrieves any post by ID, including private/deleted posts. For admin use only.
  """
  def admin_get_post(post_id) do
    Post
    |> Repo.get(post_id)
    |> case do
      nil -> {:error, :not_found}
      post -> {:ok, Repo.preload(post, [:identity, :parent, :quote, poll: :options])}
    end
  end

  @doc """
  Soft-deletes any post (sets deleted_at) with an audit log entry.
  Also publishes a Delete ActivityPub activity for federated posts.
  """
  def admin_delete_post(post_id, admin_id, reason \\ "") do
    with {:ok, post} <- admin_get_post(post_id),
         {:ok, post} <- do_admin_soft_delete(post) do
      Hybridsocial.Moderation.log(admin_id, "post.admin_deleted", "post", post_id, %{
        reason: reason,
        post_identity_id: post.identity_id
      })

      # Publish Delete activity for federated posts
      if post.ap_id do
        try do
          activity = Hybridsocial.Federation.ActivityBuilder.build_delete(post)
          Hybridsocial.Federation.Publisher.publish(activity, post.identity)
        rescue
          _ -> :ok
        end
      end

      {:ok, post}
    end
  end

  defp do_admin_soft_delete(%Post{deleted_at: nil} = post) do
    post
    |> Post.soft_delete_changeset()
    |> Repo.update()
  end

  defp do_admin_soft_delete(%Post{} = post), do: {:ok, post}

  @doc """
  Force-marks a post as sensitive with an audit log entry.
  """
  def admin_force_sensitive(post_id, admin_id) do
    with {:ok, post} <- admin_get_post(post_id) do
      case post
           |> Ecto.Changeset.change(sensitive: true)
           |> Repo.update() do
        {:ok, updated} ->
          Hybridsocial.Moderation.log(admin_id, "post.force_sensitive", "post", post_id, %{
            post_identity_id: post.identity_id
          })

          {:ok, updated}

        error ->
          error
      end
    end
  end

  @doc """
  Removes forced sensitive marking from a post with an audit log entry.
  """
  def admin_remove_sensitive(post_id, admin_id) do
    with {:ok, post} <- admin_get_post(post_id) do
      case post
           |> Ecto.Changeset.change(sensitive: false)
           |> Repo.update() do
        {:ok, updated} ->
          Hybridsocial.Moderation.log(admin_id, "post.remove_sensitive", "post", post_id, %{
            post_identity_id: post.identity_id
          })

          {:ok, updated}

        error ->
          error
      end
    end
  end

  # --- Private helpers ---

  defp get_owned_post(post_id, identity_id) do
    Post
    |> where([p], is_nil(p.deleted_at))
    |> Repo.get(post_id)
    |> case do
      nil -> {:error, :not_found}
      %Post{identity_id: ^identity_id} = post -> {:ok, post}
      _post -> {:error, :forbidden}
    end
  end

  defp get_existing_post(post_id) do
    case get_post(post_id) do
      nil -> {:error, :not_found}
      post -> {:ok, post}
    end
  end

  defp get_existing_reaction(post_id, identity_id) do
    Reaction
    |> where([r], r.post_id == ^post_id and r.identity_id == ^identity_id)
    |> Repo.one()
  end

  defp get_existing_boost(post_id, identity_id) do
    Boost
    |> where(
      [b],
      b.post_id == ^post_id and b.identity_id == ^identity_id and is_nil(b.deleted_at)
    )
    |> Repo.one()
  end

  defp update_reaction_count(post_id, delta) do
    Post
    |> where([p], p.id == ^post_id)
    |> Repo.update_all(inc: [reaction_count: delta])
  end

  defp update_boost_count(post_id, delta) do
    Post
    |> where([p], p.id == ^post_id)
    |> Repo.update_all(inc: [boost_count: delta])
  end

  defp get_next_revision_number(post_id) do
    PostRevision
    |> where([r], r.post_id == ^post_id)
    |> select([r], count(r.id))
    |> Repo.one()
    |> Kernel.+(1)
  end

  defp extract_and_link_hashtags(post) do
    tags = extract_hashtags(post.content)

    Enum.each(tags, fn tag_name ->
      {:ok, hashtag} = upsert_hashtag(tag_name)
      link_post_hashtag(post.id, hashtag.id)
    end)
  end

  defp upsert_hashtag(name) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Hashtag{}
    |> Hashtag.changeset(%{name: name})
    |> Repo.insert(
      on_conflict: [inc: [usage_count: 1]],
      conflict_target: [:name],
      returning: true,
      set: [usage_count: dynamic([h], h.usage_count + 1), updated_at: now]
    )
  end

  defp link_post_hashtag(post_id, hashtag_id) do
    {:ok, post_uuid} = Ecto.UUID.dump(post_id)
    {:ok, hashtag_uuid} = Ecto.UUID.dump(hashtag_id)

    Repo.insert_all(
      "post_hashtags",
      [%{post_id: post_uuid, hashtag_id: hashtag_uuid}],
      on_conflict: :nothing,
      conflict_target: [:post_id, :hashtag_id]
    )
  end
end

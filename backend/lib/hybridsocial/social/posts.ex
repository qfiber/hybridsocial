defmodule Hybridsocial.Social.Posts do
  @moduledoc """
  Context module for managing posts, reactions, boosts, and hashtags.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.{Post, PostRevision, Reaction, Boost, Hashtag, Polls}

  @edit_window_seconds 24 * 60 * 60
  @default_page_size 20

  # --- Post CRUD ---

  def create_post(identity_id, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    edit_expires_at =
      DateTime.add(now, @edit_window_seconds, :second)
      |> DateTime.truncate(:microsecond)

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

    changeset =
      %Post{}
      |> Post.create_changeset(post_attrs)
      |> Ecto.Changeset.put_change(:published_at, now)
      |> Ecto.Changeset.put_change(:edit_expires_at, edit_expires_at)

    case Repo.insert(changeset) do
      {:ok, post} ->
        if post.content, do: extract_and_link_hashtags(post)

        if post.post_type == "poll" do
          poll_attrs = Map.take(attrs, ["options", "multiple_choice", "expires_at"])
          Polls.create_poll(post.id, poll_attrs)
        end

        {:ok, Repo.preload(post, [poll: :options])}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def edit_post(post_id, identity_id, attrs) do
    with {:ok, post} <- get_owned_post(post_id, identity_id) do
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
        Post.edit_changeset(post, attrs)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{post: post}} ->
          if post.content, do: extract_and_link_hashtags(post)
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
      post
      |> Post.soft_delete_changeset()
      |> Repo.update()
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
        root_id = post.root_id || post.id

        ancestors =
          Post
          |> where([p], is_nil(p.deleted_at))
          |> where([p], p.id == ^root_id or p.root_id == ^root_id)
          |> where([p], p.published_at < ^post.published_at or p.id == ^root_id)
          |> where([p], p.id != ^post.id)
          |> order_by([p], asc: p.published_at)
          |> Repo.all()
          |> Repo.preload(:identity)

        descendants =
          Post
          |> where([p], is_nil(p.deleted_at))
          |> where([p], p.root_id == ^root_id or p.parent_id == ^post_id)
          |> where([p], p.published_at > ^post.published_at)
          |> where([p], p.id != ^post.id)
          |> order_by([p], asc: p.published_at)
          |> Repo.all()
          |> Repo.preload(:identity)

        {:ok, %{ancestors: ancestors, descendants: descendants}}
    end
  end

  def get_revisions(post_id) do
    PostRevision
    |> where([r], r.post_id == ^post_id)
    |> order_by([r], asc: r.revision_number)
    |> Repo.all()
  end

  # --- Reactions ---

  def react(post_id, identity_id, type) do
    with {:ok, _post} <- get_existing_post(post_id) do
      case get_existing_reaction(post_id, identity_id) do
        nil ->
          %Reaction{}
          |> Reaction.changeset(%{post_id: post_id, identity_id: identity_id, type: type})
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
          |> Reaction.changeset(%{type: type})
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
    cursor = Keyword.get(opts, :cursor)

    query =
      Post
      |> where([p], p.identity_id == ^identity_id)
      |> where([p], is_nil(p.deleted_at))
      |> order_by([p], desc: p.published_at)
      |> limit(^limit)

    query =
      if cursor do
        where(query, [p], p.published_at < ^cursor)
      else
        query
      end

    posts = Repo.all(query) |> Repo.preload([:identity, :quote])

    next_cursor =
      case List.last(posts) do
        nil -> nil
        last -> last.published_at
      end

    %{posts: posts, next_cursor: next_cursor}
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
    |> where([b], b.post_id == ^post_id and b.identity_id == ^identity_id and is_nil(b.deleted_at))
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

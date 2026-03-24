defmodule HybridsocialWeb.Api.V1.StatusController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Social.Posts
  alias Hybridsocial.Premium.TierLimits

  # POST /api/v1/statuses
  def create(conn, params) do
    identity = conn.assigns.current_identity
    limits = TierLimits.limits_for(identity)

    with :ok <- validate_tier_limits(params, limits) do
      case Posts.create_post(identity.id, params, identity) do
        {:ok, post} ->
          post = Hybridsocial.Repo.preload(post, [:identity, :quote])

          conn
          |> put_status(:created)
          |> json(serialize_post(post))

        {:error, :premium_emojis_required, shortcodes} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "premium_emojis_required", shortcodes: shortcodes})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      {:error, error_key, max} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: error_key, max: max})
    end
  end

  # GET /api/v1/statuses/:id
  def show(conn, %{"id" => id}) do
    case Posts.get_post_with_context(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      post ->
        conn
        |> put_status(:ok)
        |> json(serialize_post(post))
    end
  end

  # PUT /api/v1/statuses/:id
  def update(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity

    case Posts.edit_post(id, identity.id, params, identity) do
      {:ok, post} ->
        post = Hybridsocial.Repo.preload(post, [:identity, :quote])

        conn
        |> put_status(:ok)
        |> json(serialize_post(post))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "status.forbidden"})

      {:error, :premium_emojis_required, shortcodes} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "premium_emojis_required", shortcodes: shortcodes})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/statuses/:id
  def delete(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.delete_post(id, identity.id) do
      {:ok, _post} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "status.deleted"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "status.forbidden"})
    end
  end

  # GET /api/v1/statuses/:id/history
  def history(conn, %{"id" => id}) do
    case Posts.get_post(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      _post ->
        revisions = Posts.get_revisions(id)

        conn
        |> put_status(:ok)
        |> json(Enum.map(revisions, &serialize_revision/1))
    end
  end

  @valid_reaction_types ~w(like love care angry sad lol wow)

  # POST /api/v1/statuses/:id/react
  def react(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    type = Map.get(params, "type", "like")

    if type in @valid_reaction_types do
      case Posts.react(id, identity.id, type) do
        {:ok, reaction} ->
          conn
          |> put_status(:ok)
          |> json(%{id: reaction.id, type: reaction.type, post_id: reaction.post_id})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "status.not_found"})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "reaction.invalid_type", valid_types: @valid_reaction_types})
    end
  end

  # DELETE /api/v1/statuses/:id/react
  def unreact(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.unreact(id, identity.id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "reaction.removed"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "reaction.not_found"})
    end
  end

  # POST /api/v1/statuses/:id/boost
  def boost(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.boost(id, identity.id) do
      {:ok, _boost} ->
        # Return the original post with updated counts
        post = Posts.get_post(id)

        conn
        |> put_status(:ok)
        |> json(serialize_post(post))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/statuses/:id/boost
  def unboost(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.unboost(id, identity.id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "boost.removed"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "boost.not_found"})
    end
  end

  # GET /api/v1/statuses/:id/context
  def context(conn, %{"id" => id}) do
    case Posts.get_thread(id) do
      {:ok, %{ancestors: ancestors, descendants: descendants}} ->
        conn
        |> put_status(:ok)
        |> json(%{
          ancestors: Enum.map(ancestors, &serialize_post/1),
          descendants: Enum.map(descendants, &serialize_post/1)
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})
    end
  end

  # POST /api/v1/statuses/:id/pin
  def pin(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.pin_post(id, identity.id) do
      {:ok, post} ->
        post = Hybridsocial.Repo.preload(post, [:identity, :quote])

        conn
        |> put_status(:ok)
        |> json(serialize_post(post))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "status.forbidden"})
    end
  end

  # DELETE /api/v1/statuses/:id/pin
  def unpin(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.unpin_post(id, identity.id) do
      {:ok, post} ->
        post = Hybridsocial.Repo.preload(post, [:identity, :quote])

        conn
        |> put_status(:ok)
        |> json(serialize_post(post))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "status.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "status.forbidden"})
    end
  end

  # POST /api/v1/statuses/:id/view
  def view(conn, %{"id" => id} = params) do
    identity = conn.assigns[:current_identity]
    identity_id = if identity, do: identity.id, else: nil

    attrs = %{
      "watch_duration" => params["watch_duration"],
      "total_duration" => params["total_duration"],
      "completed" => params["completed"],
      "replayed" => params["replayed"],
      "source" => params["source"]
    }

    case Hybridsocial.Social.Streams.record_view(id, identity_id, attrs) do
      {:ok, view_record} ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: view_record.id,
          post_id: view_record.post_id,
          watch_duration: view_record.watch_duration,
          total_duration: view_record.total_duration,
          completed: view_record.completed,
          replayed: view_record.replayed,
          source: view_record.source
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # --- Serialization ---

  defp serialize_post(post) do
    badges =
      Hybridsocial.Badges.badges_for_post(
        post.identity,
        group_id: post.group_id,
        page_id: post.page_id
      )

    account = serialize_account(post.identity, badges)

    quote_post =
      case post.quote do
        %Hybridsocial.Social.Post{} = q ->
          q = Hybridsocial.Repo.preload(q, :identity)
          serialize_post(q)

        _ ->
          nil
      end

    # If the identity has force_sensitive enabled, override sensitive to true
    sensitive =
      case post.identity do
        %{force_sensitive: true} -> true
        _ -> post.sensitive
      end

    %{
      id: post.id,
      type: post.post_type,
      content: post.content,
      content_html: post.content_html,
      visibility: post.visibility,
      sensitive: sensitive,
      spoiler_text: post.spoiler_text,
      language: post.language,
      reply_count: post.reply_count,
      boost_count: post.boost_count,
      reaction_count: post.reaction_count,
      is_pinned: post.is_pinned,
      created_at: post.inserted_at,
      edited_at: post.edited_at,
      account: account,
      parent_id: post.parent_id,
      quote: quote_post
    }
  end

  defp serialize_account(%Hybridsocial.Accounts.Identity{} = identity, badges) do
    %{
      id: identity.id,
      handle: identity.handle,
      display_name: identity.display_name,
      avatar_url: identity.avatar_url,
      badges: badges
    }
  end

  defp serialize_account(_, _), do: nil

  defp serialize_revision(revision) do
    %{
      id: revision.id,
      content: revision.content,
      content_html: revision.content_html,
      edited_at: revision.edited_at,
      revision_number: revision.revision_number
    }
  end

  defp validate_tier_limits(params, limits) do
    media_ids = params["media_ids"] || []
    poll_options = params["options"] || []

    cond do
      length(media_ids) > limits[:media_per_post] ->
        {:error, "limits.media_per_post", limits[:media_per_post]}

      poll_options != [] and length(poll_options) > limits[:poll_options] ->
        {:error, "limits.poll_options", limits[:poll_options]}

      params["scheduled_at"] && !limits[:scheduled_posts] ->
        {:error, "limits.scheduled_posts_not_allowed", nil}

      true ->
        :ok
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

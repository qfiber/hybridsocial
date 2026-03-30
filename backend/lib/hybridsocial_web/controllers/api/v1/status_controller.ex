defmodule HybridsocialWeb.Api.V1.StatusController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Social.Posts
  alias Hybridsocial.Premium.TierLimits
  alias HybridsocialWeb.Serializers.PostSerializer

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
          |> json(serialize_post(conn, post))

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
        |> json(serialize_post(conn, post))
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
        |> json(serialize_post(conn, post))

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

  # GET /api/v1/statuses/:id/reactions
  def reactions(conn, %{"id" => id}) do
    import Ecto.Query

    reactions =
      Hybridsocial.Social.Reaction
      |> where([r], r.post_id == ^id)
      |> preload(:identity)
      |> Hybridsocial.Repo.all()

    grouped =
      reactions
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, entries} ->
        %{
          type: type,
          count: length(entries),
          accounts: Enum.map(entries, fn r ->
            %{
              id: r.identity.id,
              handle: r.identity.handle,
              display_name: r.identity.display_name,
              avatar_url: r.identity.avatar_url
            }
          end)
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)

    json(conn, grouped)
  end

  # POST /api/v1/statuses/:id/react
  def react(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    type = Map.get(params, "type", "like")
    custom_emoji_allowed = Hybridsocial.Premium.TierLimits.limit(identity, :custom_emoji) == true

    is_custom_emoji = String.starts_with?(type, ":") and String.ends_with?(type, ":")
    is_valid = type in @valid_reaction_types or (is_custom_emoji and custom_emoji_allowed)

    if is_valid do
      # Verify custom emoji exists
      if is_custom_emoji do
        shortcode = String.trim(type, ":")
        case Hybridsocial.Repo.get_by(Hybridsocial.Content.CustomEmoji, shortcode: shortcode, enabled: true) do
          nil ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "reaction.emoji_not_found"})

          _emoji ->
            do_react(conn, id, identity.id, type, custom_emoji_allowed)
        end
      else
        do_react(conn, id, identity.id, type, custom_emoji_allowed)
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "reaction.invalid_type", valid_types: @valid_reaction_types})
    end
  end

  defp do_react(conn, post_id, identity_id, type, custom_emoji_allowed) do
    case Posts.react(post_id, identity_id, type, custom_emoji_allowed: custom_emoji_allowed) do
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
        |> json(serialize_post(conn, post))

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
    identity_id = current_identity_id(conn)

    case Posts.get_thread(id) do
      {:ok, %{ancestors: ancestors, descendants: descendants}} ->
        serialized_ancestors =
          PostSerializer.serialize_many(ancestors, current_identity_id: identity_id)

        serialized_descendants =
          PostSerializer.serialize_many(descendants, current_identity_id: identity_id)

        # Insert tombstones for gaps (exclude the focused post itself)
        serialized_ancestors = insert_tombstones(serialized_ancestors, id)
        serialized_descendants = insert_descendant_tombstones(serialized_descendants, id)

        conn
        |> put_status(:ok)
        |> json(%{
          ancestors: serialized_ancestors,
          descendants: serialized_descendants
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
    limits = TierLimits.limits_for(identity)
    max_pins = limits[:pinned_posts] || 1

    # Check current pin count
    pinned_count = Posts.pinned_count(identity.id)

    if pinned_count >= max_pins do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "limits.max_pinned_posts", max: max_pins})
    else

    case Posts.pin_post(id, identity.id) do
      {:ok, post} ->
        post = Hybridsocial.Repo.preload(post, [:identity, :quote])

        conn
        |> put_status(:ok)
        |> json(serialize_post(conn, post))

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
  end

  # DELETE /api/v1/statuses/:id/pin
  def unpin(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Posts.unpin_post(id, identity.id) do
      {:ok, post} ->
        post = Hybridsocial.Repo.preload(post, [:identity, :quote])

        conn
        |> put_status(:ok)
        |> json(serialize_post(conn, post))

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

  defp serialize_post(conn, post) do
    PostSerializer.serialize(post, current_identity_id: current_identity_id(conn))
  end

  defp current_identity_id(conn) do
    case conn.assigns[:current_identity] do
      %{id: id} -> id
      _ -> nil
    end
  end

  # Insert tombstones for gaps in ancestor chain
  defp insert_tombstones(ancestors, focused_id) do
    known_ids = MapSet.new([focused_id | Enum.map(ancestors, & &1[:id])])

    ancestors
    |> Enum.reduce({[], nil}, fn post, {acc, _prev_id} ->
      parent = post[:parent_id]

      acc =
        if parent && !MapSet.member?(known_ids, parent) && !Enum.any?(acc, fn p -> p[:id] == parent end) do
          [PostSerializer.serialize_tombstone(parent) | acc]
        else
          acc
        end

      {acc ++ [post], post[:id]}
    end)
    |> elem(0)
  end

  # Insert tombstones for orphaned descendants
  defp insert_descendant_tombstones(descendants, focused_id) do
    known_ids = MapSet.new([focused_id | Enum.map(descendants, & &1[:id])])

    Enum.flat_map(descendants, fn post ->
      parent = post[:parent_id]

      if parent && !MapSet.member?(known_ids, parent) do
        [PostSerializer.serialize_tombstone(parent), post]
      else
        [post]
      end
    end)
    |> Enum.uniq_by(& &1[:id])
  end

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

  # POST /api/v1/statuses/:id/mute
  def mute_post(conn, %{"id" => post_id}) do
    identity = conn.assigns.current_identity

    case Hybridsocial.Social.mute_post(post_id, identity.id) do
      {:ok, _} -> json(conn, %{status: "ok"})
      _ -> json(conn, %{status: "ok"})
    end
  end

  # DELETE /api/v1/statuses/:id/mute
  def unmute_post(conn, %{"id" => post_id}) do
    identity = conn.assigns.current_identity
    Hybridsocial.Social.unmute_post(post_id, identity.id)
    json(conn, %{status: "ok"})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

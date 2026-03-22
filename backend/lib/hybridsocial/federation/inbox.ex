defmodule Hybridsocial.Federation.Inbox do
  @moduledoc """
  Main inbox processor for incoming ActivityPub activities.
  Dispatches to the appropriate handler based on activity type.
  """

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social
  alias Hybridsocial.Social.Post
  alias Hybridsocial.Federation.ActivityMapper

  require Logger

  @doc """
  Processes an incoming ActivityPub activity.
  Dispatches to the appropriate handler based on the activity's "type" field.
  Returns {:ok, result} or {:error, reason}.
  """
  def process(%{"type" => type} = activity) do
    Logger.info("Processing #{type} activity: #{activity["id"]}")

    case type do
      "Follow" -> handle_follow(activity)
      "Accept" -> handle_accept(activity)
      "Reject" -> handle_reject(activity)
      "Create" -> handle_create(activity)
      "Like" -> handle_like(activity)
      "EmojiReact" -> handle_emoji_react(activity)
      "Announce" -> handle_announce(activity)
      "Delete" -> handle_delete(activity)
      "Update" -> handle_update(activity)
      "Block" -> handle_block(activity)
      "Undo" -> handle_undo(activity)
      "Move" -> handle_move(activity)
      "Flag" -> handle_flag(activity)
      "Add" -> handle_add(activity)
      "Remove" -> handle_remove(activity)
      _ -> {:error, :unsupported_activity_type}
    end
  end

  def process(_), do: {:error, :invalid_activity}

  # --- Follow ---
  # A remote actor wants to follow a local actor.

  defp handle_follow(%{"actor" => actor_ap_id, "object" => object_ap_id} = activity)
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    with {:ok, local_identity} <- resolve_local_identity(object_ap_id),
         {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id) do
      status = if local_identity.is_locked, do: :pending, else: :accepted

      result =
        Social.follow(remote_identity.id, local_identity.id)

      case result do
        {:ok, follow} ->
          if status == :accepted do
            Logger.info("Auto-accepted follow from #{actor_ap_id}")
          end

          {:ok, %{follow: follow, activity: activity}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp handle_follow(_), do: {:error, :invalid_follow_activity}

  # --- Accept ---
  # A remote actor accepted our follow request.

  defp handle_accept(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) do
    follow_object = normalize_object(object)

    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, follow} <- find_pending_follow(follow_object, remote_identity.id) do
      Social.accept_follow(follow.id)
    end
  end

  defp handle_accept(_), do: {:error, :invalid_accept_activity}

  # --- Reject ---
  # A remote actor rejected our follow request.

  defp handle_reject(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) do
    follow_object = normalize_object(object)

    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, follow} <- find_pending_follow(follow_object, remote_identity.id) do
      Social.reject_follow(follow.id)
    end
  end

  defp handle_reject(_), do: {:error, :invalid_reject_activity}

  # --- Create ---
  # A remote actor created a new object (Note, Article, Question).

  defp handle_create(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) and is_map(object) do
    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id) do
      post_attrs = ActivityMapper.to_post(object)

      # Check if we already have this post
      case get_post_by_ap_id(post_attrs["ap_id"]) do
        nil ->
          # Resolve parent post if this is a reply
          parent_id = resolve_parent_post_id(post_attrs["parent_ap_id"])

          insert_attrs =
            post_attrs
            |> Map.delete("parent_ap_id")
            |> Map.put("identity_id", remote_identity.id)
            |> maybe_put_parent(parent_id)

          %Post{}
          |> Post.create_changeset(insert_attrs)
          |> maybe_put_published_at(post_attrs["published_at"])
          |> maybe_put_content_html(post_attrs["content_html"])
          |> Repo.insert()

        existing ->
          {:ok, existing}
      end
    end
  end

  defp handle_create(%{"actor" => actor_ap_id, "object" => object_id})
       when is_binary(actor_ap_id) and is_binary(object_id) do
    # Object is just an ID reference -- we'd need to fetch it.
    # For now, return an error since we can't process inline.
    {:error, :object_must_be_embedded}
  end

  defp handle_create(_), do: {:error, :invalid_create_activity}

  # --- Like ---

  defp handle_like(%{"actor" => actor_ap_id, "object" => object_ap_id})
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.react(post.id, remote_identity.id, "like")
    end
  end

  defp handle_like(_), do: {:error, :invalid_like_activity}

  # --- EmojiReact ---

  defp handle_emoji_react(%{
         "actor" => actor_ap_id,
         "object" => object_ap_id,
         "content" => content
       })
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    reaction_type = ActivityMapper.to_reaction_type(content)

    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.react(post.id, remote_identity.id, reaction_type)
    end
  end

  defp handle_emoji_react(_), do: {:error, :invalid_emoji_react_activity}

  # --- Announce (Boost) ---

  defp handle_announce(%{"actor" => actor_ap_id, "object" => object_ap_id})
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.boost(post.id, remote_identity.id)
    end
  end

  defp handle_announce(_), do: {:error, :invalid_announce_activity}

  # --- Delete ---

  defp handle_delete(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) do
    object_ap_id = normalize_object_id(object)

    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id) do
      case get_post_by_ap_id(object_ap_id) do
        %Post{identity_id: identity_id} = post when identity_id == remote_identity.id ->
          post
          |> Post.soft_delete_changeset()
          |> Repo.update()

        %Post{} ->
          {:error, :forbidden}

        nil ->
          # Post not found; may have already been deleted
          {:ok, :already_deleted}
      end
    end
  end

  defp handle_delete(_), do: {:error, :invalid_delete_activity}

  # --- Update ---

  defp handle_update(%{"actor" => actor_ap_id, "object" => object})
       when is_binary(actor_ap_id) and is_map(object) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id) do
      case object["type"] do
        type when type in ["Person", "Service", "Organization", "Application", "Group"] ->
          # Update the remote actor's cached info
          actor_attrs = ActivityMapper.to_actor(object)

          remote_identity
          |> Identity.update_changeset(%{
            display_name: actor_attrs[:display_name],
            avatar_url: actor_attrs[:avatar_url]
          })
          |> Repo.update()

        type when type in ["Note", "Article"] ->
          update_remote_post(object, remote_identity)

        _ ->
          {:error, :unsupported_object_type}
      end
    end
  end

  defp handle_update(_), do: {:error, :invalid_update_activity}

  # --- Block ---

  defp handle_block(%{"actor" => actor_ap_id, "object" => object_ap_id})
       when is_binary(actor_ap_id) and is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, local_identity} <- resolve_local_identity(object_ap_id) do
      Social.block(remote_identity.id, local_identity.id)
    end
  end

  defp handle_block(_), do: {:error, :invalid_block_activity}

  # --- Undo ---

  defp handle_undo(%{"actor" => actor_ap_id, "object" => %{"type" => inner_type} = inner_object})
       when is_binary(actor_ap_id) do
    case inner_type do
      "Follow" -> undo_follow(actor_ap_id, inner_object)
      "Like" -> undo_like(actor_ap_id, inner_object)
      "Announce" -> undo_announce(actor_ap_id, inner_object)
      "Block" -> undo_block(actor_ap_id, inner_object)
      _ -> {:error, :unsupported_undo_type}
    end
  end

  defp handle_undo(_), do: {:error, :invalid_undo_activity}

  # --- Undo sub-handlers ---

  defp undo_follow(actor_ap_id, %{"object" => target_ap_id})
       when is_binary(target_ap_id) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, local_identity} <- resolve_local_identity(target_ap_id) do
      Social.unfollow(remote_identity.id, local_identity.id)
      {:ok, :unfollowed}
    end
  end

  defp undo_follow(_, _), do: {:error, :invalid_undo_follow}

  defp undo_like(actor_ap_id, %{"object" => object_ap_id})
       when is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.unreact(post.id, remote_identity.id)
    end
  end

  defp undo_like(_, _), do: {:error, :invalid_undo_like}

  defp undo_announce(actor_ap_id, %{"object" => object_ap_id})
       when is_binary(object_ap_id) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, post} <- resolve_local_post(object_ap_id) do
      Hybridsocial.Social.Posts.unboost(post.id, remote_identity.id)
    end
  end

  defp undo_announce(_, _), do: {:error, :invalid_undo_announce}

  defp undo_block(actor_ap_id, %{"object" => target_ap_id})
       when is_binary(target_ap_id) do
    with {:ok, remote_identity} <- resolve_remote_identity(actor_ap_id),
         {:ok, local_identity} <- resolve_local_identity(target_ap_id) do
      Social.unblock(remote_identity.id, local_identity.id)
      {:ok, :unblocked}
    end
  end

  defp undo_block(_, _), do: {:error, :invalid_undo_block}

  # --- Flag (Report) ---

  defp handle_flag(%{"actor" => actor_ap_id, "object" => objects} = activity)
       when is_binary(actor_ap_id) do
    content = activity["content"] || ""
    reported_objects = if is_list(objects), do: objects, else: [objects]

    # The first URI is typically the reported actor, remaining are specific posts
    {reported_actor_uri, _post_uris} =
      case reported_objects do
        [actor_uri | rest] -> {actor_uri, rest}
        [] -> {nil, []}
      end

    with {:ok, remote_reporter} <- resolve_or_create_remote_identity(actor_ap_id),
         {:ok, reported_identity} <- resolve_reported_identity(reported_actor_uri) do
      Hybridsocial.Moderation.create_report(remote_reporter.id, %{
        "reported_id" => reported_identity.id,
        "category" => "other",
        "description" => content,
        "federated" => true
      })
    end
  end

  defp handle_flag(_), do: {:error, :invalid_flag_activity}

  defp resolve_reported_identity(nil), do: {:error, :no_reported_actor}

  defp resolve_reported_identity(ap_id) do
    # Try local first, then remote
    case extract_local_identity_id(ap_id) do
      nil ->
        case Repo.one(from(i in Identity, where: i.ap_actor_url == ^ap_id)) do
          nil -> {:error, :reported_identity_not_found}
          identity -> {:ok, identity}
        end

      id ->
        case Accounts.get_identity(id) do
          nil -> {:error, :reported_identity_not_found}
          identity -> {:ok, identity}
        end
    end
  end

  # --- Add (Pin) ---

  defp handle_add(%{"actor" => _actor, "object" => object, "target" => target})
       when is_binary(target) do
    if String.contains?(to_string(target), "/collections/featured") do
      case get_post_by_ap_id(to_string(object)) do
        nil -> {:error, :not_found}
        post -> post |> Ecto.Changeset.change(is_pinned: true) |> Repo.update()
      end
    else
      {:ok, :ignored}
    end
  end

  defp handle_add(_), do: {:error, :invalid_add_activity}

  # --- Remove (Unpin) ---

  defp handle_remove(%{"actor" => _actor, "object" => object, "target" => target})
       when is_binary(target) do
    if String.contains?(to_string(target), "/collections/featured") do
      case get_post_by_ap_id(to_string(object)) do
        nil -> {:error, :not_found}
        post -> post |> Ecto.Changeset.change(is_pinned: false) |> Repo.update()
      end
    else
      {:ok, :ignored}
    end
  end

  defp handle_remove(_), do: {:error, :invalid_remove_activity}

  # --- Helper functions ---

  defp resolve_local_identity(ap_id) when is_binary(ap_id) do
    case extract_local_identity_id(ap_id) do
      nil ->
        {:error, :not_local_actor}

      id ->
        case Accounts.get_identity(id) do
          nil -> {:error, :identity_not_found}
          identity -> {:ok, identity}
        end
    end
  end

  defp extract_local_identity_id(ap_id) do
    base = HybridsocialWeb.Endpoint.url()

    case String.replace_prefix(ap_id, "#{base}/actors/", "") do
      ^ap_id -> nil
      id -> id
    end
  end

  @doc """
  Resolves a remote actor to a local identity.
  Stub: In production, this looks up the remote_actors table and finds the linked identity.
  For now, we look up by ap_actor_url on identities.
  """
  def resolve_remote_identity(ap_id) when is_binary(ap_id) do
    case Repo.one(from(i in Identity, where: i.ap_actor_url == ^ap_id)) do
      nil -> {:error, :remote_identity_not_found}
      identity -> {:ok, identity}
    end
  end

  @doc """
  Resolves or creates a local identity stub for a remote actor.
  Stub: In production, this would create a remote_actor record and link it.
  For now, we create a minimal identity with the AP ID.
  """
  def resolve_or_create_remote_identity(ap_id) when is_binary(ap_id) do
    case Repo.one(from(i in Identity, where: i.ap_actor_url == ^ap_id)) do
      nil ->
        create_stub_identity_for_remote(ap_id)

      identity ->
        {:ok, identity}
    end
  end

  defp create_stub_identity_for_remote(ap_id) do
    domain = ActivityMapper.extract_domain(ap_id)
    # Extract a handle-like string from the AP ID
    handle = generate_remote_handle(ap_id, domain)

    id = Ecto.UUID.generate()

    attrs = %{
      id: id,
      type: "user",
      handle: handle,
      ap_actor_url: ap_id,
      inbox_url: "#{ap_id}/inbox",
      outbox_url: "#{ap_id}/outbox",
      followers_url: "#{ap_id}/followers"
    }

    %Identity{}
    |> Ecto.Changeset.cast(attrs, [
      :id,
      :type,
      :handle,
      :ap_actor_url,
      :inbox_url,
      :outbox_url,
      :followers_url
    ])
    |> Ecto.Changeset.validate_required([:type, :handle])
    |> Ecto.Changeset.unique_constraint(:handle)
    |> Repo.insert()
  end

  defp generate_remote_handle(ap_id, domain) do
    # Try to extract username from common AP ID patterns
    path =
      case URI.parse(ap_id) do
        %URI{path: path} when is_binary(path) -> path
        _ -> ""
      end

    username =
      path
      |> String.split("/")
      |> List.last()
      |> String.replace(~r/[^a-zA-Z0-9_]/, "")

    suffix = (domain || "unknown") |> String.replace(~r/[^a-zA-Z0-9]/, "") |> String.slice(0, 8)
    short_id = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)

    name = if username != "", do: username, else: "remote"
    "#{name}_#{suffix}_#{short_id}" |> String.slice(0, 30)
  end

  defp resolve_local_post(ap_id) when is_binary(ap_id) do
    # First try to find by ap_id (for federated posts)
    case get_post_by_ap_id(ap_id) do
      nil ->
        # Try to extract local post ID from URL
        case extract_local_post_id(ap_id) do
          nil ->
            {:error, :post_not_found}

          id ->
            case Hybridsocial.Social.Posts.get_post(id) do
              nil -> {:error, :post_not_found}
              post -> {:ok, post}
            end
        end

      post ->
        {:ok, post}
    end
  end

  defp extract_local_post_id(ap_id) do
    base = HybridsocialWeb.Endpoint.url()

    case String.replace_prefix(ap_id, "#{base}/objects/", "") do
      ^ap_id -> nil
      id -> id
    end
  end

  defp get_post_by_ap_id(nil), do: nil

  defp get_post_by_ap_id(ap_id) do
    Post
    |> where([p], p.ap_id == ^ap_id and is_nil(p.deleted_at))
    |> Repo.one()
  end

  defp resolve_parent_post_id(nil), do: nil

  defp resolve_parent_post_id(parent_ap_id) do
    case get_post_by_ap_id(parent_ap_id) do
      nil ->
        case extract_local_post_id(parent_ap_id) do
          nil -> nil
          id -> id
        end

      post ->
        post.id
    end
  end

  defp maybe_put_parent(attrs, nil), do: attrs
  defp maybe_put_parent(attrs, parent_id), do: Map.put(attrs, "parent_id", parent_id)

  defp maybe_put_content_html(changeset, nil), do: changeset

  defp maybe_put_content_html(changeset, content_html) do
    # Override the escaped HTML with the raw HTML from the AP object
    Ecto.Changeset.put_change(changeset, :content_html, content_html)
  end

  defp maybe_put_published_at(changeset, nil), do: changeset

  defp maybe_put_published_at(changeset, published_at) do
    published_at = DateTime.truncate(published_at, :microsecond)
    edit_expires = DateTime.add(published_at, 86400, :second) |> DateTime.truncate(:microsecond)

    changeset
    |> Ecto.Changeset.put_change(:published_at, published_at)
    |> Ecto.Changeset.put_change(:edit_expires_at, edit_expires)
  end

  defp normalize_object(%{"id" => id}) when is_binary(id), do: %{"id" => id}
  defp normalize_object(id) when is_binary(id), do: %{"id" => id}
  defp normalize_object(other), do: other

  defp normalize_object_id(%{"id" => id}) when is_binary(id), do: id
  defp normalize_object_id(id) when is_binary(id), do: id
  defp normalize_object_id(_), do: nil

  defp find_pending_follow(%{"id" => _follow_ap_id}, followee_id) do
    # Find a pending follow where the followee is the given identity
    follow =
      Hybridsocial.Social.Follow
      |> where([f], f.followee_id == ^followee_id and f.status == :pending)
      |> order_by([f], desc: f.inserted_at)
      |> limit(1)
      |> Repo.one()

    case follow do
      nil -> {:error, :follow_not_found}
      follow -> {:ok, follow}
    end
  end

  defp find_pending_follow(_, _), do: {:error, :invalid_follow_reference}

  # --- Move ---

  defp handle_move(activity) do
    Hybridsocial.Federation.Migration.process_move(activity)
  end

  defp update_remote_post(object, remote_identity) do
    case get_post_by_ap_id(object["id"]) do
      %Post{identity_id: identity_id} = post when identity_id == remote_identity.id ->
        attrs = %{
          "content" => object["content"],
          "sensitive" => object["sensitive"] || false,
          "spoiler_text" => object["summary"]
        }

        post
        |> Post.edit_changeset(attrs)
        |> Repo.update()

      %Post{} ->
        {:error, :forbidden}

      nil ->
        {:error, :post_not_found}
    end
  end
end

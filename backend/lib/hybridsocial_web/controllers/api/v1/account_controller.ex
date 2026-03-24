defmodule HybridsocialWeb.Api.V1.AccountController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Accounts
  alias Hybridsocial.Social
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

  def show(conn, %{"id" => id}) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "account.not_found"})

      identity ->
        conn
        |> put_status(:ok)
        |> json(serialize_identity(identity))
    end
  end

  def update(conn, params) do
    identity = conn.assigns.current_identity

    case Accounts.update_identity(identity, params) do
      {:ok, updated} ->
        conn
        |> put_status(:ok)
        |> json(serialize_identity(updated))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def delete(conn, _params) do
    identity = conn.assigns.current_identity

    case Accounts.soft_delete_identity(identity) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "account.deletion_scheduled"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def lookup(conn, %{"handle" => handle}) do
    identity =
      if String.contains?(handle, "@") do
        # Remote user: user@domain — look up by AP actor URL
        [username, domain] = String.split(handle, "@", parts: 2)

        import Ecto.Query

        Hybridsocial.Repo.one(
          from(i in Hybridsocial.Accounts.Identity,
            where:
              fragment("? LIKE ?", i.ap_actor_url, ^"%://#{domain}/%") and is_nil(i.deleted_at),
            where: fragment("split_part(?, '/', -1) = ?", i.ap_actor_url, ^username),
            limit: 1
          )
        ) || Accounts.get_identity_by_handle(handle)
      else
        Accounts.get_identity_by_handle(handle)
      end

    case identity do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "account.not_found"})

      identity ->
        conn
        |> put_status(:ok)
        |> json(serialize_identity(identity))
    end
  end

  def statuses(conn, %{"id" => id} = params) do
    case Accounts.get_identity(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "account.not_found"})

      _identity ->
        posts =
          Hybridsocial.Social.Posts.posts_by_identity(id,
            limit: clamp_limit(params["limit"])
          )

        posts_list = if is_list(posts), do: posts, else: []

        conn
        |> put_status(:ok)
        |> json(
          Enum.map(posts_list, fn post ->
            %{
              id: post.id,
              content: post.content,
              content_html: post.content_html,
              visibility: post.visibility,
              sensitive: post.sensitive,
              spoiler_text: post.spoiler_text,
              reply_count: post.reply_count,
              boost_count: post.boost_count,
              reaction_count: post.reaction_count,
              is_pinned: post.is_pinned,
              created_at: post.inserted_at,
              edited_at: post.edited_at,
              account: serialize_identity(Hybridsocial.Repo.preload(post, :identity).identity)
            }
          end)
        )
    end
  end

  # --- Social actions ---

  def follow(conn, %{"id" => target_id}) do
    identity = conn.assigns.current_identity

    case Social.follow(identity.id, target_id) do
      {:ok, follow} ->
        conn |> put_status(:ok) |> json(serialize_relationship(identity.id, target_id, follow))

      {:error, :cannot_follow_self} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "social.cannot_follow_self"})

      {:error, :blocked} ->
        conn |> put_status(:forbidden) |> json(%{error: "social.blocked"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "account.not_found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def unfollow(conn, %{"id" => target_id}) do
    identity = conn.assigns.current_identity
    :ok = Social.unfollow(identity.id, target_id)
    conn |> put_status(:ok) |> json(%{id: target_id, following: false})
  end

  def block(conn, %{"id" => target_id}) do
    identity = conn.assigns.current_identity

    case Social.block(identity.id, target_id) do
      {:ok, _block} ->
        conn |> put_status(:ok) |> json(%{id: target_id, blocking: true})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def unblock(conn, %{"id" => target_id}) do
    identity = conn.assigns.current_identity
    :ok = Social.unblock(identity.id, target_id)
    conn |> put_status(:ok) |> json(%{id: target_id, blocking: false})
  end

  def mute(conn, %{"id" => target_id} = params) do
    identity = conn.assigns.current_identity

    opts =
      []
      |> then(fn o ->
        case params["mute_notifications"] do
          nil -> o
          val -> Keyword.put(o, :mute_notifications, val)
        end
      end)
      |> then(fn o ->
        case params["expires_at"] do
          nil ->
            o

          val when is_binary(val) ->
            case DateTime.from_iso8601(val) do
              {:ok, dt, _} -> Keyword.put(o, :expires_at, dt)
              _ -> o
            end

          _ ->
            o
        end
      end)

    case Social.mute(identity.id, target_id, opts) do
      {:ok, _mute} ->
        conn |> put_status(:ok) |> json(%{id: target_id, muting: true})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def unmute(conn, %{"id" => target_id}) do
    identity = conn.assigns.current_identity
    :ok = Social.unmute(identity.id, target_id)
    conn |> put_status(:ok) |> json(%{id: target_id, muting: false})
  end

  def followers(conn, %{"id" => id}) do
    identities = Social.followers(id, conn_pagination_opts(conn))

    conn
    |> put_status(:ok)
    |> json(Enum.map(identities, &serialize_identity/1))
  end

  def following(conn, %{"id" => id}) do
    identities = Social.following(id, conn_pagination_opts(conn))

    conn
    |> put_status(:ok)
    |> json(Enum.map(identities, &serialize_identity/1))
  end

  # --- Actor Migration ---

  def migrate(conn, %{"target_account" => target_account}) do
    identity = conn.assigns.current_identity

    case Hybridsocial.Federation.Migration.initiate_migration(identity.id, target_account) do
      {:ok, updated_identity} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "migration.initiated", moved_to: updated_identity.moved_to})

      {:error, :identity_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "account.not_found"})

      {:error, :invalid_target_url} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "migration.invalid_target"})

      {:error, :target_not_linked} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "migration.target_not_linked"})

      {:error, _reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "migration.failed"})
    end
  end

  def migrate(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "migration.target_required"})
  end

  def also_known_as(conn, %{"uri" => uri}) do
    identity = conn.assigns.current_identity

    case Hybridsocial.Federation.Migration.add_also_known_as(identity.id, uri) do
      {:ok, updated_identity} ->
        conn
        |> put_status(:ok)
        |> json(%{also_known_as: updated_identity.also_known_as})

      {:error, :identity_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "account.not_found"})

      {:error, _reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "also_known_as.failed"})
    end
  end

  def also_known_as(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "also_known_as.uri_required"})
  end

  def relationships(conn, params) do
    identity = conn.assigns.current_identity
    ids = params["ids"] || params["id"] || []
    ids = if is_list(ids), do: ids, else: [ids]

    rels = Social.relationships(identity.id, ids)
    conn |> put_status(:ok) |> json(rels)
  end

  defp conn_pagination_opts(conn) do
    limit = clamp_limit(conn.params["limit"])
    offset = conn.params["offset"] |> to_integer(0)
    [limit: limit, offset: offset]
  end

  defp to_integer(nil, default), do: default

  defp to_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp to_integer(val, _default) when is_integer(val), do: val

  defp serialize_relationship(identity_id, target_id, follow) do
    %{
      id: target_id,
      following: follow.status == :accepted,
      requested: follow.status == :pending,
      followed_by: Social.following?(target_id, identity_id),
      blocking: Social.blocked?(identity_id, target_id),
      muting: Social.muted?(identity_id, target_id)
    }
  end

  defp serialize_identity(identity) do
    %{
      id: identity.id,
      type: identity.type,
      handle: identity.handle,
      display_name: identity.display_name,
      bio: identity.bio,
      avatar_url: identity.avatar_url,
      header_url: identity.header_url,
      is_locked: identity.is_locked,
      is_bot: identity.is_bot,
      is_admin: identity.is_admin,
      badges: Hybridsocial.Badges.instance_badges(identity),
      created_at: identity.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

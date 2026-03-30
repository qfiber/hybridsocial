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

    # Update user-level fields if provided
    user_updates =
      %{}
      |> then(fn m -> if params["locale"], do: Map.put(m, :locale, params["locale"]), else: m end)
      |> then(fn m -> if params["default_visibility"], do: Map.put(m, :default_visibility, params["default_visibility"]), else: m end)

    # Merge preferences map if provided
    user_updates =
      if is_map(params["preferences"]) do
        case Hybridsocial.Repo.get_by(Hybridsocial.Accounts.User, identity_id: identity.id) do
          nil -> user_updates
          user ->
            merged = Map.merge(user.preferences || %{}, params["preferences"])
            Map.put(user_updates, :preferences, merged)
        end
      else
        user_updates
      end

    if map_size(user_updates) > 0 do
      case Hybridsocial.Repo.get_by(Hybridsocial.Accounts.User, identity_id: identity.id) do
        nil -> :ok
        user ->
          user
          |> Ecto.Changeset.change(user_updates)
          |> Hybridsocial.Repo.update()
      end
    end

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
        viewer_id = case conn.assigns[:current_identity] do
          %{id: vid} -> vid
          _ -> nil
        end

        opts = [
          limit: clamp_limit(params["limit"]),
          exclude_replies: params["exclude_replies"] == "true",
          only_media: params["only_media"] == "true",
          only_direct: params["only_direct"] == "true",
          max_id: params["max_id"]
        ]

        posts =
          Hybridsocial.Social.Posts.posts_by_identity(id, opts)
          |> then(fn p -> if is_list(p), do: p, else: [] end)

        serialized = HybridsocialWeb.Serializers.PostSerializer.serialize_many(posts, current_identity_id: viewer_id)

        conn
        |> put_status(:ok)
        |> json(serialized)
    end
  end

  # --- Social actions ---

  def follow(conn, %{"id" => target_id}) do
    identity = conn.assigns.current_identity
    limits = Hybridsocial.Premium.TierLimits.limits_for(identity)
    follows_limit = limits[:follows_limit] || 0

    # Enforce follows limit (0 = unlimited)
    if follows_limit > 0 do
      current_count = Hybridsocial.Social.following_count(identity.id)
      if current_count >= follows_limit do
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "limits.max_follows", max: follows_limit})
      else
        do_follow(conn, identity, target_id)
      end
    else
      do_follow(conn, identity, target_id)
    end
  end

  defp do_follow(conn, identity, target_id) do
    case Hybridsocial.Social.follow(identity.id, target_id) do
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
      show_badge: identity.show_badge,
      badges: Hybridsocial.Badges.instance_badges(identity),
      created_at: identity.inserted_at
    }
  end

  # --- Follow Requests ---

  def follow_requests(conn, _params) do
    identity = conn.assigns.current_identity
    requests = Social.pending_follow_requests(identity.id)
    conn |> json(Enum.map(requests, fn f ->
      requester = Hybridsocial.Repo.preload(f, :follower).follower
      %{id: f.id, account: serialize_identity(requester), created_at: f.inserted_at}
    end))
  end

  def authorize_follow(conn, %{"id" => follow_id}) do
    case Social.accept_follow(follow_id) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(:not_found) |> json(%{error: "follow_request.not_found"})
    end
  end

  def reject_follow(conn, %{"id" => follow_id}) do
    case Social.reject_follow(follow_id) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(:not_found) |> json(%{error: "follow_request.not_found"})
    end
  end

  # --- Domain Blocks (user-level) ---

  def domain_blocks(conn, _params) do
    identity = conn.assigns.current_identity
    blocks = Social.list_domain_blocks(identity.id)
    json(conn, Enum.map(blocks, fn b -> %{id: b.id, domain: b.domain} end))
  end

  def block_domain(conn, %{"domain" => domain}) do
    identity = conn.assigns.current_identity
    case Social.block_domain(identity.id, domain) do
      {:ok, block} -> conn |> put_status(:created) |> json(%{id: block.id, domain: block.domain})
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "domain_block.failed", details: format_errors(changeset)})
    end
  end

  def unblock_domain(conn, %{"domain" => domain}) do
    identity = conn.assigns.current_identity
    Social.unblock_domain(identity.id, domain)
    json(conn, %{status: "ok"})
  end

  # --- Drive ---

  def drive_folders(conn, params) do
    identity = conn.assigns.current_identity
    folders = Hybridsocial.Media.Drive.list_folders(identity.id, params["parent_id"])
    json(conn, Enum.map(folders, fn f -> %{id: f.id, name: f.name, parent_id: f.parent_id, created_at: f.inserted_at} end))
  end

  def create_drive_folder(conn, params) do
    identity = conn.assigns.current_identity
    case Hybridsocial.Media.Drive.create_folder(identity.id, params) do
      {:ok, f} -> conn |> put_status(:created) |> json(%{id: f.id, name: f.name, parent_id: f.parent_id})
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "folder.failed", details: format_errors(changeset)})
    end
  end

  def rename_drive_folder(conn, %{"id" => id, "name" => name}) do
    identity = conn.assigns.current_identity
    case Hybridsocial.Media.Drive.rename_folder(id, identity.id, name) do
      {:ok, f} -> json(conn, %{id: f.id, name: f.name})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "folder.not_found"})
    end
  end

  def delete_drive_folder(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity
    case Hybridsocial.Media.Drive.delete_folder(id, identity.id) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "folder.not_found"})
    end
  end

  def drive_files(conn, params) do
    identity = conn.assigns.current_identity
    files = Hybridsocial.Media.Drive.list_files(identity.id, folder_id: params["folder_id"], max_id: params["max_id"])
    json(conn, Enum.map(files, fn f ->
      %{id: f.id, content_type: f.content_type, file_size: f.file_size, storage_path: f.storage_path, folder_id: f.folder_id, content_hash: f.content_hash, alt_text: f.alt_text, created_at: f.inserted_at}
    end))
  end

  def move_drive_files(conn, %{"file_ids" => file_ids, "folder_id" => folder_id}) do
    identity = conn.assigns.current_identity
    Hybridsocial.Media.Drive.move_files(identity.id, file_ids, folder_id)
    json(conn, %{status: "ok"})
  end

  def delete_drive_files(conn, %{"file_ids" => file_ids}) do
    identity = conn.assigns.current_identity
    {:ok, count} = Hybridsocial.Media.Drive.delete_files(identity.id, file_ids)
    json(conn, %{deleted: count})
  end

  def find_by_hash(conn, %{"hash" => hash}) do
    identity = conn.assigns.current_identity
    files = Hybridsocial.Media.Drive.find_by_hash(identity.id, hash)
    json(conn, Enum.map(files, fn f -> %{id: f.id, storage_path: f.storage_path, content_type: f.content_type} end))
  end

  def drive_usage(conn, _params) do
    identity = conn.assigns.current_identity
    usage = Hybridsocial.Media.Drive.storage_usage(identity.id)
    json(conn, usage)
  end

  # --- Excerpts ---

  def list_excerpts(conn, _params) do
    identity = conn.assigns.current_identity
    excerpts = Hybridsocial.Social.Excerpts.list_excerpts(identity.id)
    json(conn, Enum.map(excerpts, &serialize_excerpt/1))
  end

  def create_excerpt(conn, params) do
    identity = conn.assigns.current_identity
    case Hybridsocial.Social.Excerpts.create_excerpt(identity.id, params) do
      {:ok, e} -> conn |> put_status(:created) |> json(serialize_excerpt(e))
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "excerpt.failed", details: format_errors(changeset)})
    end
  end

  def show_excerpt(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity
    case Hybridsocial.Social.Excerpts.get_excerpt(id, identity.id) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "excerpt.not_found"})
      e -> json(conn, serialize_excerpt(e))
    end
  end

  def excerpt_feed(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    case Hybridsocial.Social.Excerpts.get_excerpt(id, identity.id) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "excerpt.not_found"})
      excerpt ->
        posts = Hybridsocial.Social.Excerpts.excerpt_feed(excerpt, max_id: params["max_id"])
        serialized = HybridsocialWeb.Serializers.PostSerializer.serialize_many(posts, current_identity_id: identity.id)
        json(conn, serialized)
    end
  end

  def update_excerpt(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    case Hybridsocial.Social.Excerpts.update_excerpt(id, identity.id, params) do
      {:ok, e} -> json(conn, serialize_excerpt(e))
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "excerpt.not_found"})
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "excerpt.failed", details: format_errors(changeset)})
    end
  end

  def delete_excerpt(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity
    case Hybridsocial.Social.Excerpts.delete_excerpt(id, identity.id) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "excerpt.not_found"})
    end
  end

  defp serialize_excerpt(e) do
    %{id: e.id, name: e.name, keywords: e.keywords, exclude_keywords: e.exclude_keywords, sources: e.sources, with_media_only: e.with_media_only, notify: e.notify, created_at: e.inserted_at}
  end

  # --- Boost Muting ---

  def mute_boosts(conn, %{"id" => target_id}) do
    identity = conn.assigns.current_identity
    Social.mute_boosts(identity.id, target_id)
    json(conn, %{id: target_id, muting_boosts: true})
  end

  def unmute_boosts(conn, %{"id" => target_id}) do
    identity = conn.assigns.current_identity
    Social.unmute_boosts(identity.id, target_id)
    json(conn, %{id: target_id, muting_boosts: false})
  end

  # --- Crypto Addresses ---

  def list_crypto_addresses(conn, _params) do
    identity = conn.assigns.current_identity
    addrs = Hybridsocial.Premium.list_own_crypto_addresses(identity.id)
    json(conn, Enum.map(addrs, &serialize_crypto/1))
  end

  def set_crypto_address(conn, params) do
    identity = conn.assigns.current_identity
    case Hybridsocial.Premium.set_crypto_address(identity.id, params) do
      {:ok, addr} -> conn |> put_status(:created) |> json(serialize_crypto(addr))
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "crypto.failed", details: format_errors(changeset)})
    end
  end

  def remove_crypto_address(conn, %{"coin" => coin}) do
    identity = conn.assigns.current_identity
    Hybridsocial.Premium.remove_crypto_address(identity.id, coin)
    json(conn, %{status: "ok"})
  end

  def public_crypto_addresses(conn, %{"id" => id}) do
    addrs = Hybridsocial.Premium.list_crypto_addresses(id)
    json(conn, Enum.map(addrs, &serialize_crypto/1))
  end

  defp serialize_crypto(addr) do
    %{id: addr.id, coin: addr.coin, coin_name: Hybridsocial.Premium.CryptoAddress.coin_name(addr.coin), address: addr.address, label: addr.label, is_public: addr.is_public}
  end

  # --- Familiar Followers ---

  def familiar_followers(conn, %{"id" => target_id}) do
    case conn.assigns[:current_identity] do
      %{id: viewer_id} ->
        accounts = Social.familiar_followers(viewer_id, target_id)
        json(conn, Enum.map(accounts, &serialize_identity/1))
      _ ->
        json(conn, [])
    end
  end

  # --- Favourited/Reacted Posts ---

  def favourited_posts(conn, params) do
    identity = conn.assigns.current_identity
    max_id = params["max_id"]

    posts = Hybridsocial.Social.Posts.reacted_posts(identity.id, max_id: max_id)
    serialized = HybridsocialWeb.Serializers.PostSerializer.serialize_many(posts, current_identity_id: identity.id)
    json(conn, serialized)
  end

  # --- Change Email ---

  def change_email(conn, %{"email" => new_email, "password" => password}) do
    identity = conn.assigns.current_identity
    case Accounts.change_email(identity.id, new_email, password) do
      {:ok, _} -> json(conn, %{status: "ok", message: "Confirmation email sent to #{new_email}"})
      {:error, :invalid_password} -> conn |> put_status(:forbidden) |> json(%{error: "auth.invalid_password"})
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  # --- Blocked & Muted lists ---

  def blocked_accounts(conn, _params) do
    identity = conn.assigns.current_identity
    accounts = Social.blocked_accounts(identity.id)
    json(conn, Enum.map(accounts, &serialize_identity/1))
  end

  def muted_accounts(conn, _params) do
    identity = conn.assigns.current_identity
    accounts = Social.muted_accounts(identity.id)
    json(conn, Enum.map(accounts, &serialize_identity/1))
  end

  # --- Suggested Users ---

  def suggestions(conn, _params) do
    identity = conn.assigns.current_identity
    suggestions = Accounts.suggested_users(identity.id)
    json(conn, Enum.map(suggestions, &serialize_identity/1))
  end

  # --- Content Filters ---

  def list_filters(conn, _params) do
    identity = conn.assigns.current_identity
    filters = Social.list_user_filters(identity.id)
    json(conn, Enum.map(filters, fn f ->
      %{id: f.id, phrase: f.phrase, context: f.context, action: f.action, whole_word: f.whole_word, expires_at: f.expires_at}
    end))
  end

  def create_filter(conn, params) do
    identity = conn.assigns.current_identity
    case Social.create_user_filter(identity.id, params) do
      {:ok, f} ->
        conn |> put_status(:created) |> json(%{id: f.id, phrase: f.phrase, context: f.context, action: f.action, whole_word: f.whole_word, expires_at: f.expires_at})
      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "filter.create_failed", details: format_errors(changeset)})
    end
  end

  def update_filter(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity
    case Social.update_user_filter(id, identity.id, params) do
      {:ok, f} ->
        json(conn, %{id: f.id, phrase: f.phrase, context: f.context, action: f.action, whole_word: f.whole_word, expires_at: f.expires_at})
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "filter.not_found"})
      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "filter.update_failed", details: format_errors(changeset)})
    end
  end

  def delete_filter(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity
    case Social.delete_user_filter(id, identity.id) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "filter.not_found"})
    end
  end

  # --- Followed Hashtags ---

  def followed_tags(conn, _params) do
    identity = conn.assigns.current_identity
    tags = Social.followed_tags(identity.id)
    json(conn, tags)
  end

  def follow_tag(conn, %{"name" => name}) do
    identity = conn.assigns.current_identity
    {:ok, _} = Social.follow_tag(identity.id, name)
    json(conn, %{name: String.downcase(name), following: true})
  end

  def unfollow_tag(conn, %{"name" => name}) do
    identity = conn.assigns.current_identity
    Social.unfollow_tag(identity.id, name)
    json(conn, %{name: String.downcase(name), following: false})
  end

  # --- Account Aliases ---

  def remove_alias(conn, %{"alias" => alias_uri}) do
    identity = conn.assigns.current_identity
    case Accounts.remove_alias(identity, alias_uri) do
      {:ok, updated} -> json(conn, %{also_known_as: updated.also_known_as})
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def remove_alias(conn, _), do: conn |> put_status(:bad_request) |> json(%{error: "missing_params"})

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

defmodule HybridsocialWeb.Api.V1.NotificationController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Notifications
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Post
  alias Hybridsocial.Social.Reaction
  alias Hybridsocial.Media
  import Ecto.Query
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]
  alias HybridsocialWeb.Compat

  # GET /api/v1/notifications
  def index(conn, params) do
    identity = conn.assigns.current_identity
    limit = clamp_limit(params["limit"])

    opts =
      []
      |> maybe_put(:limit, limit + 1)
      |> maybe_put(:max_id, params["max_id"])
      |> maybe_put(:types, parse_list(params["types[]"] || params["types"]))
      |> maybe_put(
        :exclude_types,
        parse_list(params["exclude_types[]"] || params["exclude_types"])
      )

    # Fetch one extra row so we can tell the client whether there's a
    # next page without making it guess from a `length >= limit`
    # heuristic. The trailing `next_cursor` is the boundary id for the
    # next request — when nil, the list is exhausted.
    fetched = Notifications.list_notifications(identity.id, opts)

    {page, next_cursor} =
      case fetched do
        list when length(list) > limit ->
          truncated = Enum.take(list, limit)
          {truncated, List.last(truncated).id}

        list ->
          {list, nil}
      end

    posts = preload_target_posts(page, Compat.mastodon?(conn))
    reactions = preload_reaction_types(page)
    serialized = Enum.map(page, &serialize_notification(&1, posts, reactions))

    if Compat.mastodon?(conn) do
      # Mastodon has no envelope: a bare array, and the cursor moves into
      # the Link header the client already follows.
      conn
      |> Compat.put_cursor_link("/api/v1/notifications", next_cursor)
      |> put_status(:ok)
      |> Compat.json(serialized, :notifications)
    else
      conn
      |> put_status(:ok)
      |> json(%{data: serialized, next_cursor: next_cursor, prev_cursor: nil})
    end
  end

  # GET /api/v1/notifications/:id
  def show(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Notifications.get_notification(id, identity.id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "notification.not_found"})

      notification ->
        posts = preload_target_posts([notification])
        reactions = preload_reaction_types([notification])

        conn
        |> put_status(:ok)
        |> Compat.json(serialize_notification(notification, posts, reactions), :notification)
    end
  end

  # POST /api/v1/notifications/clear
  def clear(conn, _params) do
    identity = conn.assigns.current_identity
    :ok = Notifications.clear_notifications(identity.id)
    conn |> put_status(:ok) |> json(%{message: "notifications.cleared"})
  end

  # GET /api/v1/notifications/unread_count
  # Lightweight count-only response so the navbar bell can hydrate
  # its unread badge on app boot without paying the cost of fetching
  # the full first page of items.
  def unread_count(conn, _params) do
    identity = conn.assigns.current_identity
    count = Notifications.unread_count(identity.id)
    conn |> put_status(:ok) |> json(%{count: count})
  end

  # POST /api/v1/notifications/:id/read
  def mark_read(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Notifications.mark_read(id, identity.id) do
      {:ok, notification} ->
        notification = Repo.preload(notification, :actor)
        posts = preload_target_posts([notification])
        reactions = preload_reaction_types([notification])
        conn |> put_status(:ok) |> json(serialize_notification(notification, posts, reactions))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "notification.not_found"})
    end
  end

  # DELETE /api/v1/notifications/:id
  def dismiss(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Notifications.dismiss_notification(id, identity.id) do
      {:ok, _notification} ->
        conn |> put_status(:ok) |> json(%{message: "notification.dismissed"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "notification.not_found"})
    end
  end

  # GET /api/v1/notification_preferences
  def preferences(conn, _params) do
    identity = conn.assigns.current_identity
    prefs = Notifications.get_preferences(identity.id)
    conn |> put_status(:ok) |> json(prefs)
  end

  # PATCH /api/v1/notification_preferences
  def update_preferences(conn, params) do
    identity = conn.assigns.current_identity
    type = params["type"]

    if is_nil(type) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "notification_preferences.type_required"})
    else
      attrs = Map.take(params, ["email", "push", "in_app"])

      case Notifications.update_preference(identity.id, type, attrs) do
        {:ok, pref} ->
          conn
          |> put_status(:ok)
          |> json(%{
            type: pref.type,
            email: pref.email,
            push: pref.push,
            in_app: pref.in_app
          })

        {:error, :forbidden} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "notification_preferences.staff_only"})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp serialize_notification(notification, posts, reactions) do
    post =
      if notification.target_type == "post" and notification.target_id do
        Map.get(posts, notification.target_id)
      end

    reaction_type =
      if notification.type == "reaction" and notification.target_type == "post" do
        Map.get(reactions, {notification.actor_id, notification.target_id})
      end

    %{
      id: notification.id,
      type: notification.type,
      created_at: notification.inserted_at,
      read: notification.read,
      account: HybridsocialWeb.Helpers.Account.serialize_summary(notification.actor),
      target_type: notification.target_type,
      target_id: notification.target_id,
      reaction_type: reaction_type,
      post: serialize_post_preview(post)
    }
  end

  # For reaction notifications, look up the actor's current reaction
  # on the post so the client can render the actual emoji instead of
  # a generic thumb. Single query keyed on (actor_id, post_id) — the
  # post-level reaction (target_media_id IS NULL) is the one the
  # bell was rung for. If the actor since cleared their reaction, the
  # row is gone and `reaction_type` falls back to nil.
  defp preload_reaction_types(notifications) do
    pairs =
      notifications
      |> Enum.filter(
        &(&1.type == "reaction" and &1.target_type == "post" and not is_nil(&1.target_id))
      )
      |> Enum.map(&{&1.actor_id, &1.target_id})
      |> Enum.uniq()

    case pairs do
      [] ->
        %{}

      _ ->
        actor_ids = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
        post_ids = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
        wanted = MapSet.new(pairs)

        Reaction
        |> where(
          [r],
          r.identity_id in ^actor_ids and r.post_id in ^post_ids and is_nil(r.target_media_id)
        )
        |> select([r], {r.identity_id, r.post_id, r.type})
        |> Repo.all()
        |> Enum.filter(fn {aid, pid, _} -> MapSet.member?(wanted, {aid, pid}) end)
        |> Map.new(fn {aid, pid, type} -> {{aid, pid}, type} end)
    end
  end

  # Look up every `post` target across the notification list in a
  # single batched query, with `media_attachments` preloaded so the
  # frontend can render either a 30-char text snippet or a small
  # thumbnail without a follow-up round trip.
  # Our own client only needs enough of the target post to render a one-line
  # preview. A Mastodon client renders the whole status inside the
  # notification row, and its `account` field is non-null, so that case gets
  # the full serialization instead.
  defp preload_target_posts(notifications, full? \\ false) do
    ids =
      notifications
      |> Enum.filter(&(&1.target_type == "post" and not is_nil(&1.target_id)))
      |> Enum.map(& &1.target_id)
      |> Enum.uniq()

    case ids do
      [] ->
        %{}

      ids ->
        preloads =
          if full?, do: [:media_attachments, :identity, :quote], else: [:media_attachments]

        posts =
          Post
          |> where([p], p.id in ^ids and is_nil(p.deleted_at))
          |> preload(^preloads)
          |> Repo.all()

        if full? do
          posts
          |> HybridsocialWeb.Serializers.PostSerializer.serialize_many([])
          |> Map.new(&{&1[:id] || &1["id"], &1})
        else
          Map.new(posts, &{&1.id, &1})
        end
    end
  end

  defp serialize_post_preview(nil), do: nil

  defp serialize_post_preview(%Post{} = post) do
    %{
      id: post.id,
      content: post.content,
      media_attachments: Enum.map(post.media_attachments || [], &serialize_media_preview/1)
    }
  end

  # Already serialized by the full path above.
  defp serialize_post_preview(%{} = post), do: post

  defp serialize_media_preview(media) do
    url = Media.media_url(media)

    %{
      id: media.id,
      type: media_type(media.content_type),
      url: url,
      preview_url: url
    }
  end

  defp media_type("image/" <> _), do: "image"
  defp media_type("video/" <> _), do: "video"
  defp media_type("audio/" <> _), do: "audio"
  defp media_type(_), do: "unknown"

  defp parse_list(nil), do: nil
  defp parse_list(list) when is_list(list), do: list

  defp parse_list(val) when is_binary(val) do
    # Accept both `types[]=a&types[]=b` (arrives as a list already)
    # and `types=a,b,c` (comma-joined, which is what our frontend's
    # query-string helper produces). Without splitting, the whole
    # comma string becomes one unmatched enum value.
    val
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

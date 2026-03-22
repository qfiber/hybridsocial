defmodule HybridsocialWeb.Api.V1.NotificationController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Notifications
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

  # GET /api/v1/notifications
  def index(conn, params) do
    identity = conn.assigns.current_identity

    opts =
      []
      |> maybe_put(:limit, clamp_limit(params["limit"]))
      |> maybe_put(:max_id, params["max_id"])
      |> maybe_put(:types, parse_list(params["types[]"] || params["types"]))
      |> maybe_put(:exclude_types, parse_list(params["exclude_types[]"] || params["exclude_types"]))

    notifications = Notifications.list_notifications(identity.id, opts)

    conn
    |> put_status(:ok)
    |> json(Enum.map(notifications, &serialize_notification/1))
  end

  # GET /api/v1/notifications/:id
  def show(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Notifications.get_notification(id, identity.id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "notification.not_found"})

      notification ->
        conn |> put_status(:ok) |> json(serialize_notification(notification))
    end
  end

  # POST /api/v1/notifications/clear
  def clear(conn, _params) do
    identity = conn.assigns.current_identity
    :ok = Notifications.clear_notifications(identity.id)
    conn |> put_status(:ok) |> json(%{message: "notifications.cleared"})
  end

  # POST /api/v1/notifications/:id/read
  def mark_read(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Notifications.mark_read(id, identity.id) do
      {:ok, notification} ->
        notification = Hybridsocial.Repo.preload(notification, :actor)
        conn |> put_status(:ok) |> json(serialize_notification(notification))

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
      conn |> put_status(:unprocessable_entity) |> json(%{error: "notification_preferences.type_required"})
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

  defp serialize_notification(notification) do
    actor = notification.actor

    %{
      id: notification.id,
      type: notification.type,
      created_at: notification.inserted_at,
      read: notification.read,
      account: %{
        id: actor.id,
        handle: actor.handle,
        display_name: actor.display_name,
        avatar_url: actor.avatar_url
      },
      target_type: notification.target_type,
      target_id: notification.target_id
    }
  end

  defp parse_list(nil), do: nil
  defp parse_list(list) when is_list(list), do: list
  defp parse_list(val) when is_binary(val), do: [val]

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

defmodule HybridsocialWeb.Api.V1.ScheduledStatusController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Content.ScheduledPosts

  # POST /api/v1/statuses/schedule
  def create(conn, params) do
    identity = conn.assigns.current_identity

    case ScheduledPosts.schedule_post(identity.id, params) do
      {:ok, post} ->
        conn
        |> put_status(:created)
        |> json(serialize_scheduled_post(post))

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})

      {:error, message} when is_binary(message) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: message})
    end
  end

  # GET /api/v1/scheduled_statuses
  def index(conn, _params) do
    identity = conn.assigns.current_identity
    posts = ScheduledPosts.get_scheduled_posts(identity.id)

    conn
    |> put_status(:ok)
    |> json(Enum.map(posts, &serialize_scheduled_post/1))
  end

  # PUT /api/v1/scheduled_statuses/:id
  def update(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity

    case ScheduledPosts.update_scheduled_post(id, identity.id, params) do
      {:ok, post} ->
        conn
        |> put_status(:ok)
        |> json(serialize_scheduled_post(post))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "scheduled_status.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "scheduled_status.forbidden"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/scheduled_statuses/:id
  def delete(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case ScheduledPosts.cancel_scheduled_post(id, identity.id) do
      {:ok, _post} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "scheduled_status.cancelled"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "scheduled_status.not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "scheduled_status.forbidden"})
    end
  end

  defp serialize_scheduled_post(post) do
    %{
      id: post.id,
      content: post.content,
      visibility: post.visibility,
      sensitive: post.sensitive,
      spoiler_text: post.spoiler_text,
      scheduled_at: post.scheduled_at,
      created_at: post.inserted_at
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

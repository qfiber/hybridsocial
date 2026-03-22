defmodule HybridsocialWeb.Api.V1.BookmarkController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Social.Bookmarks

  # POST /api/v1/statuses/:id/bookmark
  def create(conn, %{"id" => post_id}) do
    identity = conn.assigns.current_identity

    case Bookmarks.bookmark(identity.id, post_id) do
      {:ok, bookmark} ->
        conn
        |> put_status(:ok)
        |> json(%{id: bookmark.id, post_id: bookmark.post_id})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/statuses/:id/bookmark
  def delete(conn, %{"id" => post_id}) do
    identity = conn.assigns.current_identity

    case Bookmarks.unbookmark(identity.id, post_id) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "bookmark.removed"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "bookmark.not_found"})
    end
  end

  # GET /api/v1/bookmarks
  def index(conn, params) do
    identity = conn.assigns.current_identity
    limit = Map.get(params, "limit", "20") |> String.to_integer()
    cursor = Map.get(params, "cursor")

    opts = [limit: limit]
    opts = if cursor, do: Keyword.put(opts, :cursor, cursor), else: opts

    result = Bookmarks.list_bookmarks(identity.id, opts)

    posts =
      Enum.map(result.bookmarks, fn bookmark ->
        serialize_post(bookmark.post)
      end)

    conn
    |> put_status(:ok)
    |> json(%{posts: posts, next_cursor: result.next_cursor})
  end

  defp serialize_post(post) do
    account = serialize_account(post.identity)

    %{
      id: post.id,
      type: post.post_type,
      content: post.content,
      content_html: post.content_html,
      visibility: post.visibility,
      sensitive: post.sensitive,
      spoiler_text: post.spoiler_text,
      language: post.language,
      reply_count: post.reply_count,
      boost_count: post.boost_count,
      reaction_count: post.reaction_count,
      is_pinned: post.is_pinned,
      created_at: post.inserted_at,
      edited_at: post.edited_at,
      account: account,
      parent_id: post.parent_id
    }
  end

  defp serialize_account(%Hybridsocial.Accounts.Identity{} = identity) do
    %{
      id: identity.id,
      handle: identity.handle,
      display_name: identity.display_name,
      avatar_url: identity.avatar_url
    }
  end

  defp serialize_account(_), do: nil

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

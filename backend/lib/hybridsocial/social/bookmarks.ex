defmodule Hybridsocial.Social.Bookmarks do
  @moduledoc """
  Context module for managing bookmarks.
  """
  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Social.Bookmark

  @default_page_size 20

  def bookmark(identity_id, post_id) do
    %Bookmark{}
    |> Bookmark.changeset(%{identity_id: identity_id, post_id: post_id})
    |> Repo.insert()
  end

  def unbookmark(identity_id, post_id) do
    case get_bookmark(identity_id, post_id) do
      nil -> {:error, :not_found}
      bookmark -> Repo.delete(bookmark)
    end
  end

  def bookmarked?(identity_id, post_id) do
    Bookmark
    |> where([b], b.identity_id == ^identity_id and b.post_id == ^post_id)
    |> Repo.exists?()
  end

  def list_bookmarks(identity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_page_size)
    cursor = Keyword.get(opts, :cursor)

    query =
      Bookmark
      |> where([b], b.identity_id == ^identity_id)
      |> order_by([b], desc: b.inserted_at)
      |> limit(^limit)

    query =
      if cursor do
        where(query, [b], b.inserted_at < ^cursor)
      else
        query
      end

    bookmarks =
      query
      |> Repo.all()
      |> Repo.preload(post: [:identity, :quote])

    next_cursor =
      case List.last(bookmarks) do
        nil -> nil
        last -> last.inserted_at
      end

    %{bookmarks: bookmarks, next_cursor: next_cursor}
  end

  defp get_bookmark(identity_id, post_id) do
    Bookmark
    |> where([b], b.identity_id == ^identity_id and b.post_id == ^post_id)
    |> Repo.one()
  end
end

defmodule HybridsocialWeb.Api.V1.TrendController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Trending
  alias HybridsocialWeb.Helpers.TimelineAccess
  import Ecto.Query, only: [from: 2]
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

  # GET /api/v1/trends/tags
  def tags(conn, params) do
    with_access(conn, fn ->
      # Trending tags are one list built across the fediverse, so a visitor limited
      # to local content gets none, rather than a list that names remote activity.
      trending =
        if TimelineAccess.local_only?(conn) do
          []
        else
          Trending.get_trending_hashtags(
            limit: clamp_limit(Map.get(params, "limit")),
            offset: parse_int(Map.get(params, "offset"), 0)
          )
        end

      conn
      |> put_status(:ok)
      |> json(Enum.map(trending, &serialize_trending_hashtag/1))
    end)
  end

  # GET /api/v1/trends/statuses
  def statuses(conn, params) do
    with_access(conn, fn ->
      viewer_id = conn.assigns[:current_identity] && conn.assigns.current_identity.id

      trending =
        Trending.get_trending_posts(
          limit: clamp_limit(Map.get(params, "limit")),
          offset: parse_int(Map.get(params, "offset"), 0),
          viewer_id: viewer_id,
          local_only: TimelineAccess.local_only?(conn)
        )

      conn
      |> put_status(:ok)
      |> json(Enum.map(trending, &serialize_trending_post/1))
    end)
  end

  # GET /api/v1/trends/links
  def links(conn, _params) do
    with_access(conn, fn ->
      conn
      |> put_status(:ok)
      |> json([])
    end)
  end

  defp with_access(conn, fun) do
    case TimelineAccess.check(conn, :local) do
      :ok -> fun.()
      :denied -> TimelineAccess.deny(conn)
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(_val, default), do: default

  defp serialize_trending_hashtag(td) do
    # Trending stores the canonical (lowercase) tag in target_id, but
    # the UI should render the first-seen casing. Look up the row's
    # display_name once per result; fall back to the slug if the
    # hashtag was deleted between snapshot and render.
    display =
      Hybridsocial.Repo.one(
        from h in Hybridsocial.Social.Hashtag,
          where: h.name == ^td.target_id,
          select: h.display_name
      ) || td.target_id

    %{
      name: display,
      slug: td.target_id,
      score: td.score,
      metadata: td.metadata
    }
  end

  defp serialize_trending_post(%{trending: td, post: post}) do
    account =
      case post.identity do
        %Hybridsocial.Accounts.Identity{} = i ->
          %{
            id: i.id,
            handle: i.handle,
            display_name: i.display_name,
            avatar_url: HybridsocialWeb.Helpers.Account.remote_image(i.avatar_url)
          }

        _ ->
          nil
      end

    %{
      id: post.id,
      content: post.content,
      content_html: post.content_html,
      visibility: post.visibility,
      created_at: post.inserted_at,
      score: td.score,
      account: account
    }
  end
end

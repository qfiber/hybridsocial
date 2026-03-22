defmodule HybridsocialWeb.Api.V1.TrendController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Trending
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

  # GET /api/v1/trends/tags
  def tags(conn, params) do
    limit = clamp_limit(Map.get(params, "limit"))
    offset = parse_int(Map.get(params, "offset"), 0)

    trending = Trending.get_trending_hashtags(limit: limit, offset: offset)

    conn
    |> put_status(:ok)
    |> json(Enum.map(trending, &serialize_trending_hashtag/1))
  end

  # GET /api/v1/trends/statuses
  def statuses(conn, params) do
    limit = clamp_limit(Map.get(params, "limit"))
    offset = parse_int(Map.get(params, "offset"), 0)

    trending = Trending.get_trending_posts(limit: limit, offset: offset)

    conn
    |> put_status(:ok)
    |> json(Enum.map(trending, &serialize_trending_post/1))
  end

  # GET /api/v1/trends/links
  def links(conn, _params) do
    conn
    |> put_status(:ok)
    |> json([])
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
    %{
      name: td.target_id,
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
            avatar_url: i.avatar_url
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

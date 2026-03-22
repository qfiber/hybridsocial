defmodule HybridsocialWeb.Api.V1.SearchController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Search

  # GET /api/v1/search?q=...&type=...&limit=...&offset=...
  def index(conn, params) do
    query = Map.get(params, "q", "")
    type = Map.get(params, "type")
    limit = parse_int(Map.get(params, "limit"), 20)
    offset = parse_int(Map.get(params, "offset"), 0)
    viewer_id = get_viewer_id(conn)
    account_id = Map.get(params, "account_id")

    results =
      Search.search(query,
        type: type,
        limit: limit,
        offset: offset,
        viewer_id: viewer_id,
        account_id: account_id
      )

    conn
    |> put_status(:ok)
    |> json(%{
      accounts: Enum.map(results.accounts, &serialize_account/1),
      statuses: Enum.map(results.posts, &serialize_post/1),
      hashtags: Enum.map(results.hashtags, &serialize_hashtag/1),
      groups: Enum.map(results.groups, &serialize_group/1)
    })
  end

  defp get_viewer_id(conn) do
    case conn.assigns do
      %{current_identity: %{id: id}} -> id
      _ -> nil
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

  defp serialize_account(identity) do
    %{
      id: identity.id,
      handle: identity.handle,
      display_name: identity.display_name,
      avatar_url: identity.avatar_url,
      bio: identity.bio
    }
  end

  defp serialize_post(post) do
    account =
      case post.identity do
        %Hybridsocial.Accounts.Identity{} = i -> serialize_account(i)
        _ -> nil
      end

    %{
      id: post.id,
      content: post.content,
      content_html: post.content_html,
      visibility: post.visibility,
      created_at: post.inserted_at,
      account: account
    }
  end

  defp serialize_hashtag(hashtag) do
    %{
      name: hashtag.name,
      usage_count: hashtag.usage_count
    }
  end

  defp serialize_group(group) do
    %{
      id: group.id,
      name: group.name,
      description: group.description,
      visibility: group.visibility,
      member_count: group.member_count
    }
  end
end

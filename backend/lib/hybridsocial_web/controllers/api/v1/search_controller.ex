defmodule HybridsocialWeb.Api.V1.SearchController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Search
  alias HybridsocialWeb.Serializers.PostSerializer
  import HybridsocialWeb.Helpers.Pagination, only: [clamp_limit: 1]

  alias Hybridsocial.Federation.WebFinger
  alias Hybridsocial.Federation.Inbox

  # GET /api/v1/search?q=...&type=...&limit=...&offset=...&resolve=...
  def index(conn, params) do
    query = Map.get(params, "q", "") |> String.slice(0, 500)
    type = Map.get(params, "type")
    limit = clamp_limit(Map.get(params, "limit"))
    offset = parse_int(Map.get(params, "offset"), 0) |> min(10_000)
    viewer_id = get_viewer_id(conn)
    account_id = Map.get(params, "account_id")
    resolve = Map.get(params, "resolve") == "true"

    results =
      Search.search(query,
        type: type,
        limit: limit,
        offset: offset,
        viewer_id: viewer_id,
        account_id: account_id
      )

    # If resolve=true and query looks like a remote handle, try WebFinger
    accounts =
      if resolve and looks_like_remote_handle?(query) and results.accounts == [] do
        case resolve_remote_account(query) do
          {:ok, identity} -> [identity]
          _ -> []
        end
      else
        results.accounts
      end

    serialized_posts = PostSerializer.serialize_many(results.posts, current_identity_id: viewer_id)

    conn
    |> put_status(:ok)
    |> json(%{
      accounts: Enum.map(accounts, &serialize_account/1),
      posts: serialized_posts,
      statuses: serialized_posts,
      hashtags: Enum.map(results.hashtags, &serialize_hashtag/1),
      groups: Enum.map(results.groups, &serialize_group/1)
    })
  end

  # Check if query looks like @user@domain or user@domain
  defp looks_like_remote_handle?(query) do
    cleaned = String.trim(query) |> String.trim_leading("@")
    Regex.match?(~r/^[\w.-]+@[\w.-]+\.\w+$/, cleaned)
  end

  defp resolve_remote_account(query) do
    acct = String.trim(query) |> String.trim_leading("@")

    # Try WebFinger first (standard), then fallback to Mastodon API lookup
    with {:error, _} <- resolve_via_webfinger(acct) do
      resolve_via_api_lookup(acct)
    end
  end

  defp resolve_via_webfinger(acct) do
    with {:ok, %{ap_id: ap_id}} when is_binary(ap_id) <- WebFinger.finger(acct),
         {:ok, identity} <- Inbox.resolve_or_create_remote_identity(ap_id) do
      {:ok, identity}
    else
      _ -> {:error, :webfinger_failed}
    end
  end

  defp resolve_via_api_lookup(acct) do
    [user, domain] = String.split(acct, "@", parts: 2)

    # SSRF protection
    with :ok <- Hybridsocial.Security.UrlValidator.validate_domain(domain) do
      url = "https://#{domain}/api/v1/accounts/lookup?acct=#{URI.encode(user)}"

      headers = [
        {"Accept", "application/json"},
        {"User-Agent", "HybridSocial/0.1.0"}
      ]

      case HTTPoison.get(url, headers, recv_timeout: 10_000, timeout: 10_000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"url" => actor_url}} when is_binary(actor_url) ->
              # Validate the returned URL too
              with :ok <- Hybridsocial.Security.UrlValidator.validate(actor_url) do
                Inbox.resolve_or_create_remote_identity(actor_url)
              else
                _ -> {:error, :not_found}
              end

            _ ->
              {:error, :not_found}
          end

        _ ->
          {:error, :not_found}
      end
    else
      _ -> {:error, :not_found}
    end
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
      acct: HybridsocialWeb.Helpers.Account.build_acct(identity),
      display_name: identity.display_name,
      avatar_url: identity.avatar_url,
      header_url: identity.header_url,
      bio: identity.bio,
      url: identity.ap_actor_url
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

defmodule HybridsocialWeb.Api.V1.SearchController do
  use HybridsocialWeb, :controller

  require Logger

  alias Hybridsocial.Feeds.Visibility
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

    # If resolve=true and the query is a fully-qualified `@user@domain`,
    # we trigger a federation lookup unless the local DB already
    # contains an EXACT (user, domain) match. Substring matches don't
    # count — searching `@user@example.social` shouldn't be satisfied
    # by a cached `ahmad@mastodon.social` or a local `ahmad`.
    accounts =
      if resolve and looks_like_remote_handle?(query) and
           not exact_remote_match?(query, results.accounts) do
        case resolve_remote_account(query) do
          {:ok, identity} -> [identity | results.accounts]
          _ -> results.accounts
        end
      else
        results.accounts
      end

    {accounts, posts} = without_locked_if_anonymous(accounts, results.posts, viewer_id)

    serialized_posts =
      PostSerializer.serialize_many(posts, current_identity_id: viewer_id)

    conn
    |> put_status(:ok)
    |> HybridsocialWeb.Compat.json(
      %{
        accounts: Enum.map(accounts, &serialize_account/1),
        posts: serialized_posts,
        statuses: serialized_posts,
        hashtags: Enum.map(results.hashtags, &serialize_hashtag/1),
        groups: Enum.map(results.groups, &serialize_group/1)
      },
      :search
    )
  end

  # Results can come from an external index, so this filters what came back rather
  # than the query. A locked account is private to anonymous viewers.
  defp without_locked_if_anonymous(accounts, posts, nil) do
    locked =
      (Enum.map(accounts, & &1.id) ++ Enum.map(posts, & &1.identity_id))
      |> Enum.uniq()
      |> Visibility.locked_among()

    {Enum.reject(accounts, &MapSet.member?(locked, &1.id)),
     Enum.reject(posts, &MapSet.member?(locked, &1.identity_id))}
  end

  defp without_locked_if_anonymous(accounts, posts, _viewer_id), do: {accounts, posts}

  # Check if query looks like @user@domain or user@domain
  defp looks_like_remote_handle?(query) do
    cleaned = String.trim(query) |> String.trim_leading("@")
    Regex.match?(~r/^[\w.-]+@[\w.-]+\.\w+$/, cleaned)
  end

  @doc false
  # Returns true iff one of the supplied identities corresponds
  # exactly to the `user@domain` in `query` (matches both the
  # username and the host of `ap_actor_url`). Local handles never
  # count as a match for a domain-qualified query.
  def exact_remote_match?(query, identities) when is_list(identities) do
    expected = String.trim(query) |> String.trim_leading("@") |> String.downcase()

    Enum.any?(identities, fn identity ->
      case HybridsocialWeb.Helpers.Account.build_acct(identity) do
        acct when is_binary(acct) ->
          # Local accounts return just the bare handle (no @domain).
          # A domain-qualified query can never match those.
          String.contains?(acct, "@") and String.downcase(acct) == expected

        _ ->
          false
      end
    end)
  end

  defp resolve_remote_account(query) do
    acct = String.trim(query) |> String.trim_leading("@")

    # Three-stage fallback chain. Each stage logs its outcome so
    # operators can trace federation problems without grep-debugging.
    cond_result =
      cond_walk([
        {"webfinger", fn -> resolve_via_webfinger(acct) end},
        {"api_lookup", fn -> resolve_via_api_lookup(acct) end},
        {"actor_convention", fn -> resolve_via_actor_convention(acct) end}
      ])

    case cond_result do
      {:ok, identity, stage} ->
        Logger.info(
          "[search] resolved remote account acct=#{acct} via=#{stage} id=#{identity.id}"
        )

        {:ok, identity}

      {:error, attempts} ->
        Logger.warning(
          "[search] could not resolve remote account acct=#{acct} attempts=#{inspect(attempts)}"
        )

        {:error, :not_found}
    end
  end

  # Walks a list of {stage_name, thunk} pairs, returning the first
  # successful {:ok, identity, stage} or {:error, attempts} where
  # attempts is a [{stage, reason}] list of every failure.
  defp cond_walk(stages), do: cond_walk(stages, [])

  defp cond_walk([], attempts), do: {:error, Enum.reverse(attempts)}

  defp cond_walk([{stage, thunk} | rest], attempts) do
    case thunk.() do
      {:ok, identity} ->
        {:ok, identity, stage}

      {:error, reason} ->
        cond_walk(rest, [{stage, reason} | attempts])

      other ->
        cond_walk(rest, [{stage, other} | attempts])
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
        {"User-Agent", Hybridsocial.Instance.user_agent()}
      ]

      case Hybridsocial.HTTP.get(url, headers, recv_timeout: 10_000, timeout: 10_000) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"url" => actor_url}} when is_binary(actor_url) ->
              # Validate the returned URL too
              with :ok <- Hybridsocial.Security.UrlValidator.validate(actor_url) do
                Inbox.resolve_or_create_remote_identity(actor_url)
              else
                _ -> {:error, :url_validation_failed}
              end

            _ ->
              {:error, :api_response_missing_url}
          end

        {:ok, %{status_code: status}} ->
          {:error, {:api_status, status}}

        {:error, reason} ->
          {:error, {:api_error, reason}}
      end
    else
      _ -> {:error, :domain_validation_failed}
    end
  end

  # Last-resort: assume the canonical /users/{user} URL pattern that
  # Mastodon, Pleroma, Akkoma and Misskey all expose, and dereference
  # the actor JSON directly. Lets us federate with instances whose
  # WebFinger and Mastodon-API discovery are both broken (e.g.
  # some instances, where nginx swallows /.well-known/* before it
  # reaches Pleroma).
  #
  # We *probe* the URL before calling resolve_or_create — that
  # function unconditionally inserts an identity stub on first sight,
  # and we don't want to pollute the DB with rows for guessed URLs
  # that don't actually exist.
  defp resolve_via_actor_convention(acct) do
    [user, domain] = String.split(acct, "@", parts: 2)

    with :ok <- Hybridsocial.Security.UrlValidator.validate_domain(domain) do
      actor_url = "https://#{domain}/users/#{URI.encode(user)}"

      with :ok <- Hybridsocial.Security.UrlValidator.validate(actor_url),
           {:ok, _actor_json} <- probe_actor_json(actor_url),
           {:ok, identity} <- Inbox.resolve_or_create_remote_identity(actor_url) do
        {:ok, identity}
      else
        {:error, reason} -> {:error, {:actor_convention, reason}}
        _ -> {:error, :actor_convention_failed}
      end
    else
      _ -> {:error, :domain_validation_failed}
    end
  end

  # Confirms the URL actually serves an ActivityPub actor before we
  # commit a row to the DB.
  defp probe_actor_json(url) do
    headers = [
      {"Accept", "application/activity+json, application/ld+json"},
      {"User-Agent", Hybridsocial.Instance.user_agent()}
    ]

    case Hybridsocial.HTTP.get(url, headers,
           recv_timeout: 10_000,
           timeout: 10_000,
           follow_redirect: true
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        with {:ok, json} <- Jason.decode(body),
             type when type in ~w(Person Organization Group Service Application) <-
               json["type"] do
          {:ok, json}
        else
          _ -> {:error, :not_an_actor}
        end

      {:ok, %{status_code: status}} ->
        {:error, {:probe_status, status}}

      {:error, reason} ->
        {:error, {:probe_error, reason}}
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
      avatar_url: HybridsocialWeb.Helpers.Account.remote_image(identity.avatar_url),
      header_url: HybridsocialWeb.Helpers.Account.remote_image(identity.header_url),
      bio: identity.bio,
      url: identity.ap_actor_url
    }
  end

  defp serialize_hashtag(hashtag) do
    %{
      name: hashtag.display_name || hashtag.name,
      slug: hashtag.name,
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

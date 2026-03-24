defmodule Hybridsocial.Search.Backends.MeilisearchBackend do
  @moduledoc """
  Meilisearch search backend.

  Communicates with a Meilisearch instance over its HTTP API.
  Configuration is read from the database-backed `Hybridsocial.Config` store:

  - `meilisearch_url` — base URL (default `http://localhost:7700`)
  - `meilisearch_api_key` — API key for authentication
  """

  @behaviour Hybridsocial.Search.Backend

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.{Post, Hashtag}
  alias Hybridsocial.Groups.Group

  require Logger

  @default_limit 20
  @max_limit 40

  @impl true
  def search_accounts(query, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    body = %{
      q: query,
      limit: limit,
      offset: offset,
      attributesToRetrieve: ["id"]
    }

    case meili_search("accounts", body) do
      {:ok, hits} ->
        ids = Enum.map(hits, & &1["id"])

        identities =
          Identity
          |> where([i], i.id in ^ids)
          |> where([i], is_nil(i.deleted_at))
          |> where([i], i.is_suspended == false)
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        results = ids |> Enum.map(&Map.get(identities, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("Meilisearch accounts search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def search_posts(query, viewer_id, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    account_id = Keyword.get(opts, :account_id)

    filter = build_post_filter(viewer_id, account_id)

    body = %{
      q: query,
      limit: limit,
      offset: offset,
      attributesToRetrieve: ["id"],
      sort: ["published_at:desc"],
      filter: filter
    }

    case meili_search("posts", body) do
      {:ok, hits} ->
        ids = Enum.map(hits, & &1["id"])

        posts =
          Post
          |> where([p], p.id in ^ids)
          |> where([p], is_nil(p.deleted_at))
          |> Repo.all()
          |> Repo.preload(:identity)
          |> Map.new(&{&1.id, &1})

        results = ids |> Enum.map(&Map.get(posts, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("Meilisearch posts search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def search_hashtags(query, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    body = %{
      q: query,
      limit: limit,
      offset: offset,
      attributesToRetrieve: ["id"],
      sort: ["usage_count:desc"]
    }

    case meili_search("hashtags", body) do
      {:ok, hits} ->
        ids = Enum.map(hits, & &1["id"])

        hashtags =
          Hashtag
          |> where([h], h.id in ^ids)
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        results = ids |> Enum.map(&Map.get(hashtags, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("Meilisearch hashtags search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def search_groups(query, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    viewer_id = Keyword.get(opts, :viewer_id)

    filter =
      if viewer_id do
        "visibility IN [public, private, local_only]"
      else
        "visibility IN [public, private]"
      end

    body = %{
      q: query,
      limit: limit,
      offset: offset,
      attributesToRetrieve: ["id"],
      filter: filter,
      sort: ["member_count:desc"]
    }

    case meili_search("groups", body) do
      {:ok, hits} ->
        ids = Enum.map(hits, & &1["id"])

        groups =
          Group
          |> where([g], g.id in ^ids)
          |> where([g], is_nil(g.deleted_at))
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        results = ids |> Enum.map(&Map.get(groups, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("Meilisearch groups search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def healthy? do
    url = meili_url() <> "/health"
    headers = auth_headers()

    case HTTPoison.get(url, headers, recv_timeout: 5_000) do
      {:ok, %{status_code: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @impl true
  def name, do: "Meilisearch"

  # --- Private helpers ---

  defp meili_search(index, body) do
    url = meili_url() <> "/indexes/#{index}/search"
    headers = [{"Content-Type", "application/json"} | auth_headers()]
    encoded = Jason.encode!(body)

    case HTTPoison.post(url, encoded, headers, recv_timeout: 15_000) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"hits" => hits}} -> {:ok, hits}
          {:error, reason} -> {:error, reason}
        end

      {:ok, %{status_code: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp meili_url do
    Hybridsocial.Config.get("meilisearch_url", "http://localhost:7700")
  end

  defp auth_headers do
    case Hybridsocial.Config.get("meilisearch_api_key") do
      nil -> []
      "" -> []
      key -> [{"Authorization", "Bearer #{key}"}]
    end
  end

  defp build_post_filter(viewer_id, account_id) do
    visibility_part =
      if viewer_id do
        "(visibility = public OR identity_id = #{viewer_id})"
      else
        "visibility = public"
      end

    parts = [visibility_part]

    parts =
      if account_id do
        ["identity_id = #{account_id}" | parts]
      else
        parts
      end

    Enum.join(parts, " AND ")
  end

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp parse_offset(opts) do
    opts
    |> Keyword.get(:offset, 0)
    |> max(0)
  end
end

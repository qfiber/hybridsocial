defmodule Hybridsocial.Search.Backends.OpensearchBackend do
  @moduledoc """
  OpenSearch search backend.

  Uses the `Hybridsocial.Search.OpenSearch` HTTP client to query an OpenSearch cluster,
  then resolves hit IDs back to Ecto structs from the database.
  """

  @behaviour Hybridsocial.Search.Backend

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.{Post, Hashtag}
  alias Hybridsocial.Groups.Group
  alias Hybridsocial.Search.OpenSearch

  require Logger

  @default_limit 20
  @max_limit 40

  @impl true
  def search_accounts(query, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    os_query = %{
      query: %{
        multi_match: %{
          query: query,
          fields: ["handle^3", "display_name^2", "bio"],
          fuzziness: "AUTO",
          type: "best_fields"
        }
      }
    }

    case OpenSearch.search("hybridsocial_accounts", os_query, size: limit, from: offset) do
      {:ok, %{hits: hits}} ->
        ids = Enum.map(hits, & &1.id)

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
        Logger.warning("OpenSearch accounts search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def search_posts(query, viewer_id, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    account_id = Keyword.get(opts, :account_id)

    filters = [%{term: %{visibility: "public"}}]

    filters =
      if viewer_id do
        [
          %{
            bool: %{
              should: [%{term: %{visibility: "public"}}, %{term: %{identity_id: viewer_id}}],
              minimum_should_match: 1
            }
          }
          | List.delete_at(filters, 0)
        ]
      else
        filters
      end

    filters =
      if account_id do
        [%{term: %{identity_id: account_id}} | filters]
      else
        filters
      end

    os_query = %{
      query: %{
        bool: %{
          must: %{
            match: %{
              content: %{
                query: query,
                fuzziness: "AUTO"
              }
            }
          },
          filter: filters
        }
      },
      sort: [%{published_at: %{order: "desc"}}]
    }

    case OpenSearch.search("hybridsocial_posts", os_query, size: limit, from: offset) do
      {:ok, %{hits: hits}} ->
        ids = Enum.map(hits, & &1.id)

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
        Logger.warning("OpenSearch posts search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def search_hashtags(query, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    os_query = %{
      query: %{
        prefix: %{
          "name.raw": %{value: String.downcase(query)}
        }
      },
      sort: [%{usage_count: %{order: "desc"}}]
    }

    case OpenSearch.search("hybridsocial_hashtags", os_query, size: limit, from: offset) do
      {:ok, %{hits: hits}} ->
        ids = Enum.map(hits, & &1.id)

        hashtags =
          Hashtag
          |> where([h], h.id in ^ids)
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        results = ids |> Enum.map(&Map.get(hashtags, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("OpenSearch hashtags search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def search_groups(query, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    viewer_id = Keyword.get(opts, :viewer_id)

    visibility_filter =
      if viewer_id do
        %{terms: %{visibility: ["public", "private", "local_only"]}}
      else
        %{terms: %{visibility: ["public", "private"]}}
      end

    os_query = %{
      query: %{
        bool: %{
          must: %{
            multi_match: %{
              query: query,
              fields: ["name^2", "description"],
              fuzziness: "AUTO"
            }
          },
          filter: [visibility_filter]
        }
      },
      sort: [%{member_count: %{order: "desc"}}]
    }

    case OpenSearch.search("hybridsocial_groups", os_query, size: limit, from: offset) do
      {:ok, %{hits: hits}} ->
        ids = Enum.map(hits, & &1.id)

        groups =
          Group
          |> where([g], g.id in ^ids)
          |> where([g], is_nil(g.deleted_at))
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        results = ids |> Enum.map(&Map.get(groups, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("OpenSearch groups search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def healthy? do
    case HTTPoison.get(opensearch_url() <> "/_cluster/health", [], recv_timeout: 5_000) do
      {:ok, %{status_code: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @impl true
  def name, do: "OpenSearch"

  # --- Private helpers ---

  defp opensearch_url do
    Application.get_env(:hybridsocial, :opensearch_url, "http://localhost:9200")
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

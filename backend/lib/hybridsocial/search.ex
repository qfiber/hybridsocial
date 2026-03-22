defmodule Hybridsocial.Search do
  @moduledoc """
  Search context. Provides full-text search across posts, accounts, hashtags, and groups.
  Supports OpenSearch as the primary backend with PostgreSQL tsvector/tsquery as fallback.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.{Post, Hashtag}
  alias Hybridsocial.Groups.Group
  alias Hybridsocial.Search.OpenSearch

  require Logger

  @default_limit 20
  @max_limit 40

  @doc """
  Returns the configured search backend: \"opensearch\" or \"postgresql\".
  """
  def search_backend do
    Application.get_env(:hybridsocial, :search_backend, "postgresql")
  end

  @doc """
  Unified search across all types. Returns a map with results for each type.
  """
  def search(query_string, opts \\ []) do
    type = Keyword.get(opts, :type)
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    viewer_id = Keyword.get(opts, :viewer_id)
    account_id = Keyword.get(opts, :account_id)

    type_opts = [limit: limit, offset: offset, viewer_id: viewer_id, account_id: account_id]

    case type do
      "accounts" ->
        %{accounts: search_accounts(query_string, type_opts), posts: [], hashtags: [], groups: []}

      "posts" ->
        %{accounts: [], posts: search_posts(query_string, viewer_id, type_opts), hashtags: [], groups: []}

      "hashtags" ->
        %{accounts: [], posts: [], hashtags: search_hashtags(query_string, type_opts), groups: []}

      "groups" ->
        %{accounts: [], posts: [], hashtags: [], groups: search_groups(query_string, type_opts)}

      _ ->
        %{
          accounts: search_accounts(query_string, type_opts),
          posts: search_posts(query_string, viewer_id, type_opts),
          hashtags: search_hashtags(query_string, type_opts),
          groups: search_groups(query_string, type_opts)
        }
    end
  end

  @doc """
  Search accounts. Uses OpenSearch when available, falls back to PostgreSQL.
  """
  def search_accounts(query_string, opts \\ []) do
    sanitized = sanitize_query(query_string)

    if sanitized == "" do
      []
    else
      if search_backend() == "opensearch" do
        case opensearch_search_accounts(sanitized, opts) do
          {:ok, results} -> results
          {:error, _reason} -> pg_search_accounts(sanitized, opts)
        end
      else
        pg_search_accounts(sanitized, opts)
      end
    end
  end

  @doc """
  Full-text search on posts. Uses OpenSearch when available, falls back to PostgreSQL.
  """
  def search_posts(query_string, viewer_id, opts \\ []) do
    sanitized = sanitize_query(query_string)

    if sanitized == "" do
      []
    else
      if search_backend() == "opensearch" do
        case opensearch_search_posts(sanitized, viewer_id, opts) do
          {:ok, results} -> results
          {:error, _reason} -> pg_search_posts(sanitized, viewer_id, opts)
        end
      else
        pg_search_posts(sanitized, viewer_id, opts)
      end
    end
  end

  @doc """
  ILIKE search on hashtags. Uses OpenSearch when available, falls back to PostgreSQL.
  """
  def search_hashtags(query_string, opts \\ []) do
    sanitized = sanitize_query(query_string)

    if sanitized == "" do
      []
    else
      if search_backend() == "opensearch" do
        case opensearch_search_hashtags(sanitized, opts) do
          {:ok, results} -> results
          {:error, _reason} -> pg_search_hashtags(sanitized, opts)
        end
      else
        pg_search_hashtags(sanitized, opts)
      end
    end
  end

  @doc """
  Search groups by name/description. Uses OpenSearch when available, falls back to PostgreSQL.
  """
  def search_groups(query_string, opts \\ []) do
    sanitized = sanitize_query(query_string)

    if sanitized == "" do
      []
    else
      if search_backend() == "opensearch" do
        case opensearch_search_groups(sanitized, opts) do
          {:ok, results} -> results
          {:error, _reason} -> pg_search_groups(sanitized, opts)
        end
      else
        pg_search_groups(sanitized, opts)
      end
    end
  end

  # --- OpenSearch Search Implementations ---

  defp opensearch_search_accounts(sanitized, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    query = %{
      query: %{
        multi_match: %{
          query: sanitized,
          fields: ["handle^3", "display_name^2", "bio"],
          fuzziness: "AUTO",
          type: "best_fields"
        }
      }
    }

    case OpenSearch.search("hybridsocial_accounts", query, size: limit, from: offset) do
      {:ok, %{hits: hits}} ->
        ids = Enum.map(hits, & &1.id)

        identities =
          Identity
          |> where([i], i.id in ^ids)
          |> where([i], is_nil(i.deleted_at))
          |> where([i], i.is_suspended == false)
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        # Preserve OpenSearch relevance ordering
        results = Enum.map(ids, &Map.get(identities, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("OpenSearch accounts search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp opensearch_search_posts(sanitized, viewer_id, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    account_id = Keyword.get(opts, :account_id)

    filters = [%{term: %{visibility: "public"}}]

    filters =
      if viewer_id do
        [%{bool: %{should: [%{term: %{visibility: "public"}}, %{term: %{identity_id: viewer_id}}], minimum_should_match: 1}} | List.delete_at(filters, 0)]
      else
        filters
      end

    filters =
      if account_id do
        [%{term: %{identity_id: account_id}} | filters]
      else
        filters
      end

    query = %{
      query: %{
        bool: %{
          must: %{
            match: %{
              content: %{
                query: sanitized,
                fuzziness: "AUTO"
              }
            }
          },
          filter: filters
        }
      },
      sort: [%{published_at: %{order: "desc"}}]
    }

    case OpenSearch.search("hybridsocial_posts", query, size: limit, from: offset) do
      {:ok, %{hits: hits}} ->
        ids = Enum.map(hits, & &1.id)

        posts =
          Post
          |> where([p], p.id in ^ids)
          |> where([p], is_nil(p.deleted_at))
          |> Repo.all()
          |> Repo.preload(:identity)
          |> Map.new(&{&1.id, &1})

        results = Enum.map(ids, &Map.get(posts, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("OpenSearch posts search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp opensearch_search_hashtags(sanitized, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    query = %{
      query: %{
        prefix: %{
          "name.raw": %{value: String.downcase(sanitized)}
        }
      },
      sort: [%{usage_count: %{order: "desc"}}]
    }

    case OpenSearch.search("hybridsocial_hashtags", query, size: limit, from: offset) do
      {:ok, %{hits: hits}} ->
        ids = Enum.map(hits, & &1.id)

        hashtags =
          Hashtag
          |> where([h], h.id in ^ids)
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        results = Enum.map(ids, &Map.get(hashtags, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("OpenSearch hashtags search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp opensearch_search_groups(sanitized, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    viewer_id = Keyword.get(opts, :viewer_id)

    visibility_filter =
      if viewer_id do
        %{terms: %{visibility: ["public", "private", "local_only"]}}
      else
        %{terms: %{visibility: ["public", "private"]}}
      end

    query = %{
      query: %{
        bool: %{
          must: %{
            multi_match: %{
              query: sanitized,
              fields: ["name^2", "description"],
              fuzziness: "AUTO"
            }
          },
          filter: [visibility_filter]
        }
      },
      sort: [%{member_count: %{order: "desc"}}]
    }

    case OpenSearch.search("hybridsocial_groups", query, size: limit, from: offset) do
      {:ok, %{hits: hits}} ->
        ids = Enum.map(hits, & &1.id)

        groups =
          Group
          |> where([g], g.id in ^ids)
          |> where([g], is_nil(g.deleted_at))
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        results = Enum.map(ids, &Map.get(groups, &1)) |> Enum.reject(&is_nil/1)
        {:ok, results}

      {:error, reason} ->
        Logger.warning("OpenSearch groups search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- PostgreSQL Search Implementations (fallback) ---

  defp pg_search_accounts(sanitized, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    tsquery = prefix_tsquery(sanitized)
    ilike_pattern = "#{escape_like(sanitized)}%"

    Identity
    |> where([i], is_nil(i.deleted_at))
    |> where([i], i.is_suspended == false)
    |> where(
      [i],
      fragment("? @@ to_tsquery('english', ?)", i.search_vector, ^tsquery) or
        ilike(i.handle, ^ilike_pattern)
    )
    |> order_by([i], asc: i.handle)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp pg_search_posts(sanitized, viewer_id, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    account_id = Keyword.get(opts, :account_id)
    tsquery = prefix_tsquery(sanitized)

    query =
      Post
      |> where([p], is_nil(p.deleted_at))
      |> where([p], fragment("? @@ to_tsquery('english', ?)", p.search_vector, ^tsquery))
      |> apply_visibility_filter(viewer_id)
      |> apply_account_filter(account_id)
      |> order_by([p], desc: p.published_at)
      |> limit(^limit)
      |> offset(^offset)

    Repo.all(query)
    |> Repo.preload(:identity)
  end

  defp pg_search_hashtags(sanitized, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    ilike_pattern = "%#{escape_like(sanitized)}%"

    Hashtag
    |> where([h], ilike(h.name, ^ilike_pattern))
    |> order_by([h], desc: h.usage_count)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp pg_search_groups(sanitized, opts) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)
    viewer_id = Keyword.get(opts, :viewer_id)
    ilike_pattern = "%#{escape_like(sanitized)}%"

    query =
      Group
      |> where([g], is_nil(g.deleted_at))
      |> where([g], ilike(g.name, ^ilike_pattern) or ilike(g.description, ^ilike_pattern))
      |> apply_group_visibility_filter(viewer_id)
      |> order_by([g], desc: g.member_count)
      |> limit(^limit)
      |> offset(^offset)

    Repo.all(query)
  end

  # --- Private helpers ---

  defp apply_visibility_filter(query, nil) do
    where(query, [p], p.visibility == "public")
  end

  defp apply_visibility_filter(query, viewer_id) do
    where(query, [p], p.visibility == "public" or p.identity_id == ^viewer_id)
  end

  defp apply_account_filter(query, nil), do: query

  defp apply_account_filter(query, account_id) do
    where(query, [p], p.identity_id == ^account_id)
  end

  defp apply_group_visibility_filter(query, nil) do
    where(query, [g], g.visibility in [:public, :private])
  end

  defp apply_group_visibility_filter(query, viewer_id) do
    where(
      query,
      [g],
      g.visibility in [:public, :private] or
        g.id in subquery(
          from(gm in "group_members",
            where: gm.identity_id == ^viewer_id and gm.status == "approved",
            select: gm.group_id
          )
        )
    )
  end

  defp sanitize_query(nil), do: ""
  defp sanitize_query(query) when is_binary(query) do
    query
    |> String.trim()
    |> String.replace(~r/[^\w\s@.-]/u, "")
    |> String.slice(0, 100)
  end

  defp prefix_tsquery(sanitized) do
    sanitized
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&("#{&1}:*"))
    |> Enum.join(" & ")
  end

  defp escape_like(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
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

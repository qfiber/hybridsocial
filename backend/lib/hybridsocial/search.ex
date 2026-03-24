defmodule Hybridsocial.Search do
  @moduledoc """
  Search context. Provides full-text search across posts, accounts, hashtags, and groups.

  Delegates to the configured search backend via `Hybridsocial.Search.BackendResolver`.
  If the primary backend fails, automatically falls back to PostgreSQL.
  """

  alias Hybridsocial.Search.BackendResolver

  require Logger

  @default_limit 20
  @max_limit 40

  @doc """
  Returns the configured search backend module.
  """
  def search_backend, do: BackendResolver.impl()

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
        %{
          accounts: [],
          posts: search_posts(query_string, viewer_id, type_opts),
          hashtags: [],
          groups: []
        }

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
  Search accounts. Uses the configured backend with PostgreSQL fallback.
  """
  def search_accounts(query_string, opts \\ []) do
    sanitized = sanitize_query(query_string)
    if sanitized == "", do: [], else: do_search(:search_accounts, [sanitized, opts])
  end

  @doc """
  Full-text search on posts. Uses the configured backend with PostgreSQL fallback.
  """
  def search_posts(query_string, viewer_id, opts \\ []) do
    sanitized = sanitize_query(query_string)
    if sanitized == "", do: [], else: do_search(:search_posts, [sanitized, viewer_id, opts])
  end

  @doc """
  Search hashtags. Uses the configured backend with PostgreSQL fallback.
  """
  def search_hashtags(query_string, opts \\ []) do
    sanitized = sanitize_query(query_string)
    if sanitized == "", do: [], else: do_search(:search_hashtags, [sanitized, opts])
  end

  @doc """
  Search groups. Uses the configured backend with PostgreSQL fallback.
  """
  def search_groups(query_string, opts \\ []) do
    sanitized = sanitize_query(query_string)
    if sanitized == "", do: [], else: do_search(:search_groups, [sanitized, opts])
  end

  # --- Private helpers ---

  defp do_search(function, args) do
    backend = BackendResolver.impl()
    fallback = BackendResolver.fallback()

    try do
      case apply(backend, function, args) do
        {:ok, results} ->
          results

        {:error, reason} ->
          Logger.warning(
            "Search backend #{backend.name()} failed for #{function}: #{inspect(reason)}, falling back to #{fallback.name()}"
          )

          fallback_search(fallback, function, args)
      end
    rescue
      e ->
        Logger.error(
          "Search backend #{inspect(backend)} raised for #{function}: #{Exception.message(e)}, falling back to #{fallback.name()}"
        )

        fallback_search(fallback, function, args)
    end
  end

  defp fallback_search(fallback, function, args) do
    case apply(fallback, function, args) do
      {:ok, results} -> results
      {:error, _reason} -> []
    end
  end

  defp sanitize_query(nil), do: ""

  defp sanitize_query(query) when is_binary(query) do
    query
    |> String.trim()
    |> String.replace(~r/[^\w\s@.-]/u, "")
    |> String.slice(0, 100)
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

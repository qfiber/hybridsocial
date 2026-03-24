defmodule Hybridsocial.Search.BackendResolver do
  @moduledoc """
  Resolves the active search backend implementation based on runtime configuration.

  The configured backend is read from the database-backed `Hybridsocial.Config` store,
  defaulting to PostgreSQL when no preference is set.
  """

  @doc "Returns the currently configured search backend module."
  @spec impl() :: module()
  def impl do
    case Hybridsocial.Config.get("search_backend", "postgresql") do
      "opensearch" -> Hybridsocial.Search.Backends.OpensearchBackend
      "meilisearch" -> Hybridsocial.Search.Backends.MeilisearchBackend
      _ -> Hybridsocial.Search.Backends.PostgresqlBackend
    end
  end

  @doc "Returns the fallback backend (always PostgreSQL)."
  @spec fallback() :: module()
  def fallback, do: Hybridsocial.Search.Backends.PostgresqlBackend
end

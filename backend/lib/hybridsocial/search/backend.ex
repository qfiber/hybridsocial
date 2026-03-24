defmodule Hybridsocial.Search.Backend do
  @moduledoc """
  Behaviour defining the contract for search backends.

  Each backend must implement search across accounts, posts, hashtags, and groups,
  plus a health check and a human-readable name.
  """

  @callback search_accounts(query :: String.t(), opts :: keyword()) ::
              {:ok, [struct()]} | {:error, term()}

  @callback search_posts(query :: String.t(), viewer_id :: String.t() | nil, opts :: keyword()) ::
              {:ok, [struct()]} | {:error, term()}

  @callback search_hashtags(query :: String.t(), opts :: keyword()) ::
              {:ok, [struct()]} | {:error, term()}

  @callback search_groups(query :: String.t(), opts :: keyword()) ::
              {:ok, [struct()]} | {:error, term()}

  @callback healthy?() :: boolean()

  @callback name() :: String.t()
end

defmodule Hybridsocial.Media.StorageBackend do
  @moduledoc """
  Behaviour for media storage backends.

  Each backend must implement `store/2`, `delete/1`, `url/1`, and `name/0`.
  Backends are resolved at runtime via `Hybridsocial.Media.StorageResolver`.
  """

  @doc "Store an upload and return `{:ok, storage_path}` on success."
  @callback store(upload :: Plug.Upload.t(), identity_id :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Delete a previously stored file by its storage path."
  @callback delete(storage_path :: String.t()) :: :ok | {:error, term()}

  @doc "Return the public URL for the given storage path."
  @callback url(storage_path :: String.t()) :: String.t()

  @doc "Return a human-readable name for this backend (e.g. `\"local\"`)."
  @callback name() :: String.t()
end

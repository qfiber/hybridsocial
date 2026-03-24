defmodule Hybridsocial.Media.StorageResolver do
  @moduledoc """
  Resolves the active storage backend module at runtime based on the
  `storage_backend` configuration setting.

  Supported values: `"local"` (default), `"s3"`, `"r2"`.
  """

  @doc "Return the storage backend module for the current configuration."
  @spec impl() :: module()
  def impl do
    case Hybridsocial.Config.get("storage_backend", "local") do
      "s3" -> Hybridsocial.Media.Backends.S3
      "r2" -> Hybridsocial.Media.Backends.R2
      _ -> Hybridsocial.Media.Backends.Local
    end
  end
end

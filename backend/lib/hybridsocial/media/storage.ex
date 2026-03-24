defmodule Hybridsocial.Media.Storage do
  @moduledoc """
  Handles file storage for media uploads.

  Delegates to the active storage backend resolved at runtime by
  `Hybridsocial.Media.StorageResolver`. Supported backends:

    - `"local"` — local filesystem (default)
    - `"s3"`    — Amazon S3 / S3-compatible services
    - `"r2"`    — Cloudflare R2

  ## Media subdomain security (production)

  In production, media should be served from a separate subdomain/domain with:
    - No cookies (use a different domain, not just a subdomain of the app domain)
    - `Content-Security-Policy: default-src 'none'` header
    - `X-Content-Type-Options: nosniff` header
    - `Content-Disposition: attachment` for non-image types

  Configure the `media_host` setting to point to your media domain (e.g. "https://media.example.com").
  """

  require Logger

  alias Hybridsocial.Media.StorageResolver

  @doc """
  Stores an uploaded file using the configured storage backend.
  Returns {:ok, storage_path} or {:error, reason}.
  """
  def store(%Plug.Upload{} = upload, identity_id) do
    StorageResolver.impl().store(upload, identity_id)
  end

  @doc """
  Deletes a file from the configured storage backend.
  """
  def delete(storage_path) do
    StorageResolver.impl().delete(storage_path)
  end

  @doc """
  Returns the public URL for a stored file.
  """
  def url(storage_path) do
    StorageResolver.impl().url(storage_path)
  end

  # ---------------------------------------------------------------------------
  # Public helpers
  # ---------------------------------------------------------------------------

  @doc """
  Returns the base uploads directory for local storage.
  """
  def uploads_dir do
    Hybridsocial.Media.Backends.Local.uploads_dir()
  end

  @doc """
  Returns the current storage backend setting.
  """
  def storage_backend do
    Hybridsocial.Config.get("storage_backend", "local")
  end
end

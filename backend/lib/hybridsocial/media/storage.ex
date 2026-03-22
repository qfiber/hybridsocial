defmodule Hybridsocial.Media.Storage do
  @moduledoc """
  Handles file storage for media uploads.

  Supports local filesystem and S3-compatible storage backends.
  The active backend is determined by the `storage_backend` instance config setting.

  ## Media subdomain security (production)

  In production, media should be served from a separate subdomain/domain with:
    - No cookies (use a different domain, not just a subdomain of the app domain)
    - `Content-Security-Policy: default-src 'none'` header
    - `X-Content-Type-Options: nosniff` header
    - `Content-Disposition: attachment` for non-image types

  Configure the `media_host` setting to point to your media domain (e.g. "https://media.example.com").
  """

  @doc """
  Stores an uploaded file using the configured storage backend.
  Returns {:ok, storage_path} or {:error, reason}.
  """
  def store(%Plug.Upload{} = upload, identity_id) do
    case storage_backend() do
      "s3" -> store_s3(upload, identity_id)
      _ -> store_local(upload, identity_id)
    end
  end

  @doc """
  Deletes a file from the configured storage backend.
  """
  def delete(storage_path) do
    case storage_backend() do
      "s3" -> delete_s3(storage_path)
      _ -> delete_local(storage_path)
    end
  end

  @doc """
  Returns the public URL for a stored file.

  For local storage: `{media_host}/uploads/{path}`
  For S3: `{media_host}/{path}` or S3 bucket URL
  """
  def url(storage_path) do
    media_host = Hybridsocial.Config.get("media_host", default_media_host())

    case storage_backend() do
      "s3" ->
        if media_host != "" do
          "#{String.trim_trailing(media_host, "/")}/#{storage_path}"
        else
          s3_url(storage_path)
        end

      _ ->
        if media_host != "" do
          "#{String.trim_trailing(media_host, "/")}/uploads/#{storage_path}"
        else
          "/uploads/#{storage_path}"
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Local storage
  # ---------------------------------------------------------------------------

  @doc """
  Stores an uploaded file to local filesystem storage.
  Returns {:ok, storage_path} or {:error, reason}.
  """
  def store_local(%Plug.Upload{path: source_path, content_type: content_type}, _identity_id) do
    uuid = Ecto.UUID.generate()
    ext = extension_from_content_type(content_type)
    now = DateTime.utc_now()
    prefix = content_type_prefix(content_type)

    relative_path =
      Path.join([
        prefix,
        Integer.to_string(now.year),
        now.month |> Integer.to_string() |> String.pad_leading(2, "0"),
        "#{uuid}.#{ext}"
      ])

    dest_path = full_path(relative_path)

    with :ok <- File.mkdir_p(Path.dirname(dest_path)),
         :ok <- File.cp(source_path, dest_path) do
      {:ok, relative_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a file from local filesystem storage.
  """
  def delete_local(storage_path) do
    path = full_path(storage_path)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # S3 storage
  # ---------------------------------------------------------------------------

  @doc """
  Stores an uploaded file to S3-compatible storage.
  Returns {:ok, storage_path} or {:error, reason}.

  S3 configuration is read from environment variables:
    - S3_BUCKET
    - S3_REGION
    - S3_ACCESS_KEY_ID
    - S3_SECRET_ACCESS_KEY
    - S3_ENDPOINT (optional, for S3-compatible services like MinIO)
  """
  def store_s3(%Plug.Upload{path: source_path, content_type: content_type}, _identity_id) do
    uuid = Ecto.UUID.generate()
    ext = extension_from_content_type(content_type)
    now = DateTime.utc_now()
    prefix = content_type_prefix(content_type)

    relative_path =
      Path.join([
        prefix,
        Integer.to_string(now.year),
        now.month |> Integer.to_string() |> String.pad_leading(2, "0"),
        "#{uuid}.#{ext}"
      ])

    bucket = s3_bucket()

    case File.read(source_path) do
      {:ok, file_binary} ->
        s3_opts = [content_type: content_type, acl: :public_read]
        request = ExAws.S3.put_object(bucket, relative_path, file_binary, s3_opts)

        case ExAws.request(request, s3_request_overrides()) do
          {:ok, _response} -> {:ok, relative_path}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a file from S3-compatible storage.
  """
  def delete_s3(storage_path) do
    bucket = s3_bucket()
    request = ExAws.S3.delete_object(bucket, storage_path)

    case ExAws.request(request, s3_request_overrides()) do
      {:ok, _response} -> :ok
      {:error, {:http_error, 404, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Public helpers
  # ---------------------------------------------------------------------------

  @doc """
  Returns the base uploads directory for local storage.
  """
  def uploads_dir do
    Path.join(:code.priv_dir(:hybridsocial), "uploads")
  end

  @doc """
  Returns the current storage backend setting.
  """
  def storage_backend do
    Hybridsocial.Config.get("storage_backend", "local")
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp full_path(relative_path) do
    Path.join(uploads_dir(), relative_path)
  end

  defp default_media_host do
    ""
  end

  defp s3_bucket do
    Hybridsocial.Config.get("s3_bucket", System.get_env("S3_BUCKET", ""))
  end

  defp s3_url(storage_path) do
    bucket = s3_bucket()
    region = Hybridsocial.Config.get("s3_region", System.get_env("S3_REGION", "us-east-1"))
    endpoint = Hybridsocial.Config.get("s3_endpoint", System.get_env("S3_ENDPOINT", ""))

    if endpoint != "" do
      "#{String.trim_trailing(endpoint, "/")}/#{bucket}/#{storage_path}"
    else
      "https://#{bucket}.s3.#{region}.amazonaws.com/#{storage_path}"
    end
  end

  defp s3_request_overrides do
    endpoint = Hybridsocial.Config.get("s3_endpoint", System.get_env("S3_ENDPOINT", ""))

    if endpoint != "" do
      uri = URI.parse(endpoint)
      [host: uri.host, port: uri.port, scheme: uri.scheme]
    else
      []
    end
  end

  defp content_type_prefix("image/" <> _), do: "images"
  defp content_type_prefix("video/" <> _), do: "videos"
  defp content_type_prefix("audio/" <> _), do: "audio"
  defp content_type_prefix(_), do: "other"

  defp extension_from_content_type("image/jpeg"), do: "jpg"
  defp extension_from_content_type("image/png"), do: "png"
  defp extension_from_content_type("image/gif"), do: "gif"
  defp extension_from_content_type("image/webp"), do: "webp"
  defp extension_from_content_type("video/mp4"), do: "mp4"
  defp extension_from_content_type("video/webm"), do: "webm"
  defp extension_from_content_type(_), do: "bin"
end

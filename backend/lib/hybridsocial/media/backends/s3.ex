defmodule Hybridsocial.Media.Backends.S3 do
  @moduledoc """
  S3-compatible storage backend.

  Configuration is read from `Hybridsocial.Config` with fallbacks to
  environment variables:

    - `s3_bucket`   / `S3_BUCKET`
    - `s3_region`   / `S3_REGION` (default `"us-east-1"`)
    - `s3_endpoint` / `S3_ENDPOINT` (optional, for MinIO and similar)

  AWS credentials are expected in the standard `AWS_ACCESS_KEY_ID` and
  `AWS_SECRET_ACCESS_KEY` environment variables (used by ExAws).
  """

  @behaviour Hybridsocial.Media.StorageBackend

  require Logger

  # ---------------------------------------------------------------------------
  # Behaviour callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def store(%Plug.Upload{path: source_path, content_type: content_type}, _identity_id) do
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
          {:ok, _response} ->
            {:ok, relative_path}

          {:error, reason} ->
            Logger.error("S3 upload failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("S3 file read failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete(storage_path) do
    bucket = s3_bucket()
    request = ExAws.S3.delete_object(bucket, storage_path)

    case ExAws.request(request, s3_request_overrides()) do
      {:ok, _response} ->
        :ok

      {:error, {:http_error, 404, _}} ->
        :ok

      {:error, reason} ->
        Logger.error("S3 delete failed for #{storage_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def url(storage_path) do
    case Application.get_env(:hybridsocial, :media_host) do
      host when is_binary(host) and host != "" ->
        "#{String.trim_trailing(host, "/")}/#{storage_path}"

      _ ->
        s3_url(storage_path)
    end
  end

  @impl true
  def name, do: "s3"

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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

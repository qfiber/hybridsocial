defmodule Hybridsocial.Media.Backends.R2 do
  @moduledoc """
  Cloudflare R2 storage backend.

  R2 is S3-compatible, so this backend uses `ExAws.S3` under the hood with
  R2-specific endpoint construction.

  Configuration is read from `Hybridsocial.Config`:

    - `r2_account_id`  — Cloudflare account ID
    - `r2_access_key`  — R2 API token access key
    - `r2_secret_key`  — R2 API token secret key
    - `r2_bucket`      — R2 bucket name
    - `media_host`     — (optional) custom domain for public URLs

  The R2 S3-compatible endpoint is:
  `https://{account_id}.r2.cloudflarestorage.com`
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

    bucket = r2_bucket()

    case File.read(source_path) do
      {:ok, file_binary} ->
        s3_opts = [content_type: content_type]
        request = ExAws.S3.put_object(bucket, relative_path, file_binary, s3_opts)

        case ExAws.request(request, r2_request_overrides()) do
          {:ok, _response} ->
            {:ok, relative_path}

          {:error, reason} ->
            Logger.error("R2 upload failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("R2 file read failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete(storage_path) do
    bucket = r2_bucket()
    request = ExAws.S3.delete_object(bucket, storage_path)

    case ExAws.request(request, r2_request_overrides()) do
      {:ok, _response} ->
        :ok

      {:error, {:http_error, 404, _}} ->
        :ok

      {:error, reason} ->
        Logger.error("R2 delete failed for #{storage_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def url(storage_path) do
    case Application.get_env(:hybridsocial, :media_host) do
      host when is_binary(host) and host != "" ->
        "#{String.trim_trailing(host, "/")}/#{storage_path}"

      _ ->
        r2_public_url(storage_path)
    end
  end

  @impl true
  def name, do: "r2"

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp r2_account_id do
    Hybridsocial.Config.get("r2_account_id", System.get_env("R2_ACCOUNT_ID", ""))
  end

  defp r2_access_key do
    Hybridsocial.Config.get("r2_access_key", System.get_env("R2_ACCESS_KEY", ""))
  end

  defp r2_secret_key do
    Hybridsocial.Config.get("r2_secret_key", System.get_env("R2_SECRET_KEY", ""))
  end

  defp r2_bucket do
    Hybridsocial.Config.get("r2_bucket", System.get_env("R2_BUCKET", ""))
  end

  defp r2_endpoint do
    "https://#{r2_account_id()}.r2.cloudflarestorage.com"
  end

  defp r2_public_url(storage_path) do
    bucket = r2_bucket()
    "#{r2_endpoint()}/#{bucket}/#{storage_path}"
  end

  defp r2_request_overrides do
    uri = URI.parse(r2_endpoint())

    [
      host: uri.host,
      port: uri.port,
      scheme: uri.scheme,
      access_key_id: r2_access_key(),
      secret_access_key: r2_secret_key(),
      region: "auto"
    ]
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

defmodule Hybridsocial.Media.Backends.Local do
  @moduledoc """
  Local filesystem storage backend.

  Files are stored under `priv/uploads/{prefix}/{year}/{month}/{uuid}.{ext}`.
  Public URLs are constructed using the `media_host` configuration setting
  when available, falling back to a relative `/uploads/` path.
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

    dest_path = full_path(relative_path)

    with :ok <- File.mkdir_p(Path.dirname(dest_path)),
         :ok <- File.cp(source_path, dest_path) do
      {:ok, relative_path}
    else
      {:error, reason} ->
        Logger.error("Local storage failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete(storage_path) do
    path = full_path(storage_path)

    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.error("Local delete failed for #{storage_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def url(storage_path) do
    media_host = Hybridsocial.Config.get("media_host", "")

    if media_host != "" do
      "#{String.trim_trailing(media_host, "/")}/uploads/#{storage_path}"
    else
      "/uploads/#{storage_path}"
    end
  end

  @impl true
  def name, do: "local"

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @doc false
  def uploads_dir do
    Path.join(:code.priv_dir(:hybridsocial), "uploads")
  end

  defp full_path(relative_path) do
    Path.join(uploads_dir(), relative_path)
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

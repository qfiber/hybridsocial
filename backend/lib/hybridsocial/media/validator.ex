defmodule Hybridsocial.Media.Validator do
  @moduledoc """
  Validates media files by checking magic bytes and file size.
  """

  # Default file size limits in bytes
  @default_image_limit 10 * 1024 * 1024
  @default_video_limit 100 * 1024 * 1024

  @doc """
  Validates the content type of a file by checking its magic bytes.
  Returns {:ok, content_type} or {:error, :invalid_content_type}.
  """
  def validate_content_type(binary_data) when is_binary(binary_data) do
    cond do
      jpeg?(binary_data) -> {:ok, "image/jpeg"}
      png?(binary_data) -> {:ok, "image/png"}
      gif?(binary_data) -> {:ok, "image/gif"}
      webp?(binary_data) -> {:ok, "image/webp"}
      mp4?(binary_data) -> {:ok, "video/mp4"}
      webm?(binary_data) -> {:ok, "video/webm"}
      true -> {:error, :invalid_content_type}
    end
  end

  @doc """
  Validates the file size against configurable limits per content type.
  Returns :ok or {:error, :file_too_large}.
  """
  def validate_file_size(size, content_type) do
    limit = size_limit(content_type)

    if size <= limit do
      :ok
    else
      {:error, :file_too_large}
    end
  end

  @doc """
  Strips metadata from a file (EXIF, etc.).
  Currently a no-op; actual stripping requires libvips.
  """
  def strip_metadata(_file_path) do
    :ok
  end

  # Magic byte checks

  # JPEG: FF D8 FF
  defp jpeg?(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: true
  defp jpeg?(_), do: false

  # PNG: 89 50 4E 47 0D 0A 1A 0A
  defp png?(<<0x89, 0x50, 0x4E, 0x47, _rest::binary>>), do: true
  defp png?(_), do: false

  # GIF: 47 49 46 38
  defp gif?(<<0x47, 0x49, 0x46, 0x38, _rest::binary>>), do: true
  defp gif?(_), do: false

  # WebP: RIFF....WEBP
  defp webp?(<<0x52, 0x49, 0x46, 0x46, _size::binary-size(4), 0x57, 0x45, 0x42, 0x50, _rest::binary>>), do: true
  defp webp?(_), do: false

  # MP4: ftyp at offset 4
  defp mp4?(<<_size::binary-size(4), 0x66, 0x74, 0x79, 0x70, _rest::binary>>), do: true
  defp mp4?(_), do: false

  # WebM: 1A 45 DF A3
  defp webm?(<<0x1A, 0x45, 0xDF, 0xA3, _rest::binary>>), do: true
  defp webm?(_), do: false

  defp size_limit("image/" <> _), do: @default_image_limit
  defp size_limit("video/" <> _), do: @default_video_limit
  defp size_limit(_), do: @default_image_limit
end

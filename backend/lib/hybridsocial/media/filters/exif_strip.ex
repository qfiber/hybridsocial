defmodule Hybridsocial.Media.Filters.ExifStrip do
  @moduledoc """
  Strips EXIF metadata from uploaded images using exiftool.

  If exiftool is not available, silently skips stripping.
  """

  require Logger

  @doc "Strip EXIF data from the file at the given path."
  def filter(%{path: path, content_type: content_type} = file_info) do
    if image_type?(content_type) and exiftool_available?() do
      case System.cmd("exiftool", ["-all=", "-overwrite_original", path], stderr_to_stdout: true) do
        {_output, 0} ->
          {:ok, file_info}

        {output, _code} ->
          Logger.warning("exiftool EXIF strip failed: #{output}")
          # Non-fatal — continue without stripping
          {:ok, file_info}
      end
    else
      {:ok, file_info}
    end
  end

  def filter(file_info), do: {:ok, file_info}

  defp image_type?("image/" <> _), do: true
  defp image_type?(_), do: false

  defp exiftool_available? do
    case System.find_executable("exiftool") do
      nil -> false
      _ -> true
    end
  end
end

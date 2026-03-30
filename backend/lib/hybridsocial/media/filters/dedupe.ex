defmodule Hybridsocial.Media.Filters.Dedupe do
  @moduledoc """
  Renames uploaded files to their content hash for deduplication.

  Files with identical content will map to the same storage path,
  preventing duplicate storage.
  """

  @doc "Rename the file to its SHA-256 content hash."
  def filter(%{path: path, filename: filename} = file_info) do
    case File.read(path) do
      {:ok, data} ->
        hash = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
        extension = Path.extname(filename)
        new_filename = hash <> extension

        {:ok, %{file_info | filename: new_filename}}

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  def filter(file_info), do: {:ok, file_info}
end

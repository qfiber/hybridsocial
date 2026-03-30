defmodule Hybridsocial.Media.Filters.Anonymize do
  @moduledoc """
  Generates a random filename for uploaded files to prevent
  information leakage through original filenames.
  """

  @doc "Replace the filename with a random UUID."
  def filter(%{filename: filename} = file_info) do
    extension = Path.extname(filename)
    random_name = Ecto.UUID.generate() <> extension
    {:ok, %{file_info | filename: random_name}}
  end

  def filter(file_info), do: {:ok, file_info}
end

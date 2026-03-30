defmodule Hybridsocial.Media.Filter do
  @moduledoc """
  Media upload filter pipeline.

  Runs uploaded files through a configurable chain of filters
  (EXIF stripping, deduplication, anonymization, etc.).
  """

  alias Hybridsocial.Config

  require Logger

  @doc """
  Runs a file through all configured upload filters.

  Takes a map with :path (file path), :filename, and :content_type.
  Returns {:ok, updated_map} or {:error, reason}.
  """
  def filter(file_info) do
    filters = configured_filters()

    Enum.reduce_while(filters, {:ok, file_info}, fn filter_mod, {:ok, acc} ->
      case filter_mod.filter(acc) do
        {:ok, updated} ->
          {:cont, {:ok, updated}}

        {:error, reason} ->
          Logger.warning("Upload filter #{inspect(filter_mod)} failed: #{inspect(reason)}")
          {:halt, {:error, reason}}
      end
    end)
  end

  defp configured_filters do
    case Config.get("upload_filters", []) do
      filters when is_list(filters) and length(filters) > 0 ->
        filters
        |> Enum.map(&resolve_filter_module/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        # Default filter pipeline
        [
          Hybridsocial.Media.Filters.ExifStrip,
          Hybridsocial.Media.Filters.Dedupe
        ]
    end
  end

  defp resolve_filter_module(name) when is_binary(name) do
    module_name = "Elixir.Hybridsocial.Media.Filters.#{name}"

    try do
      String.to_existing_atom(module_name)
    rescue
      ArgumentError -> nil
    end
  end

  defp resolve_filter_module(module) when is_atom(module), do: module
  defp resolve_filter_module(_), do: nil
end

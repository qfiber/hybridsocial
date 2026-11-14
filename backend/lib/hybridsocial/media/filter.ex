defmodule Hybridsocial.Media.Filter do
  @moduledoc """
  Media upload filter pipeline.

  Runs uploaded files through a configurable chain of filters
  (EXIF stripping, deduplication, anonymization, etc.).
  """

  alias Hybridsocial.Config
  alias Hybridsocial.Media.Filters.{Anonymize, Dedupe, ExifStrip}

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

  # Metadata stripping always runs first: it removes location and device data
  # from photos, so it must not be one checkbox away from being switched off.
  # `upload_filters` picks the optional ones; unset keeps the old default
  # (Dedupe), an empty list means none.
  @optional %{"Dedupe" => Dedupe, "Anonymize" => Anonymize}

  @doc "The filter modules to run, in order."
  def configured_filters do
    optional =
      case Config.get("upload_filters") do
        nil ->
          [Dedupe]

        names when is_list(names) ->
          names |> Enum.map(&Map.get(@optional, &1)) |> Enum.reject(&is_nil/1)

        _ ->
          [Dedupe]
      end

    Enum.uniq([ExifStrip | optional])
  end
end

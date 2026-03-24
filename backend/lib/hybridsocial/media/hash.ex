defmodule Hybridsocial.Media.Hash do
  @moduledoc """
  Computes file content hashes and checks them against the media hash ban list.

  Used in the upload pipeline to reject known-banned media before storage.
  """

  alias Hybridsocial.Moderation

  @doc """
  Computes the SHA256 hash of a file at the given path.
  Returns `{:ok, hex_hash}` or `{:error, reason}`.
  """
  def compute_hash(file_path) do
    case File.read(file_path) do
      {:ok, binary_data} ->
        hash =
          :crypto.hash(:sha256, binary_data)
          |> Base.encode16(case: :lower)

        {:ok, hash}

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Computes the SHA256 hash of raw binary data.
  Returns the hex-encoded hash string.
  """
  def compute_hash_from_binary(binary_data) when is_binary(binary_data) do
    :crypto.hash(:sha256, binary_data)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Computes the hash of an upload file and checks it against the ban list.
  Returns `:ok` if the file is not banned, or `{:error, :banned_media}` if it is.
  """
  def check_upload(file_path) do
    case compute_hash(file_path) do
      {:ok, hash} ->
        if Moderation.media_hash_banned?(hash) do
          {:error, :banned_media}
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end

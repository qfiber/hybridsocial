defmodule Hybridsocial.Media do
  @moduledoc """
  The Media context. Manages file uploads, validation, storage, and retrieval.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Media.{MediaFile, Storage, Validator}

  @doc """
  Uploads a file: validates magic bytes, validates size, stores to disk, creates DB record.
  Returns {:ok, media} or {:error, reason}.
  """
  def upload(identity_id, %Plug.Upload{path: path, filename: filename} = upload) do
    with {:ok, binary_data} <- File.read(path),
         {:ok, content_type} <- Validator.validate_content_type(binary_data),
         file_size <- byte_size(binary_data),
         :ok <- Validator.validate_file_size(file_size, content_type),
         :ok <- Validator.strip_metadata(path),
         {:ok, storage_path} <- Storage.store(%{upload | content_type: content_type}, identity_id) do
      attrs = %{
        identity_id: identity_id,
        content_type: content_type,
        file_size: file_size,
        storage_path: storage_path,
        processing_status: "ready",
        metadata: %{"original_filename" => filename}
      }

      %MediaFile{}
      |> MediaFile.create_changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Uploads a file with optional alt_text.
  """
  def upload(identity_id, %Plug.Upload{} = upload, alt_text) when is_binary(alt_text) do
    case upload(identity_id, upload) do
      {:ok, media} ->
        media
        |> MediaFile.update_alt_text_changeset(%{alt_text: alt_text})
        |> Repo.update()

      error ->
        error
    end
  end

  def upload(identity_id, %Plug.Upload{} = upload, _alt_text) do
    upload(identity_id, upload)
  end

  @doc """
  Gets a media record by ID, excluding soft-deleted records.
  """
  def get_media(id) do
    MediaFile
    |> where([m], is_nil(m.deleted_at))
    |> Repo.get(id)
  end

  @doc """
  Gets a media record by ID, excluding soft-deleted records. Raises if not found.
  """
  def get_media!(id) do
    MediaFile
    |> where([m], is_nil(m.deleted_at))
    |> Repo.get!(id)
  end

  @doc """
  Updates the alt text for a media record. Verifies ownership.
  """
  def update_alt_text(media_id, identity_id, alt_text) do
    case get_media(media_id) do
      nil ->
        {:error, :not_found}

      %MediaFile{identity_id: ^identity_id} = media ->
        media
        |> MediaFile.update_alt_text_changeset(%{alt_text: alt_text})
        |> Repo.update()

      %MediaFile{} ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Soft-deletes a media record. Verifies ownership.
  The actual file cleanup can be scheduled separately.
  """
  def delete_media(media_id, identity_id) do
    case get_media(media_id) do
      nil ->
        {:error, :not_found}

      %MediaFile{identity_id: ^identity_id} = media ->
        media
        |> MediaFile.soft_delete_changeset()
        |> Repo.update()

      %MediaFile{} ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Returns the public URL for a media record.
  Uses the media_host config setting if available for URL generation.
  """
  def media_url(%MediaFile{storage_path: storage_path}) do
    Storage.url(storage_path)
  end

  def media_url(nil), do: nil
end

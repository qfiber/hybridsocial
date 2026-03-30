defmodule Hybridsocial.Media.Drive do
  @moduledoc "User media drive — folders, search, bulk operations."

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Media.{DriveFolder, MediaFile}

  # --- Folders ---

  def list_folders(identity_id, parent_id \\ nil) do
    DriveFolder
    |> where([f], f.identity_id == ^identity_id)
    |> then(fn q ->
      if parent_id, do: where(q, [f], f.parent_id == ^parent_id), else: where(q, [f], is_nil(f.parent_id))
    end)
    |> order_by([f], asc: f.name)
    |> Repo.all()
  end

  def create_folder(identity_id, attrs) do
    %DriveFolder{}
    |> DriveFolder.changeset(Map.put(attrs, "identity_id", identity_id))
    |> Repo.insert()
  end

  def rename_folder(id, identity_id, name) do
    case Repo.get_by(DriveFolder, id: id, identity_id: identity_id) do
      nil -> {:error, :not_found}
      folder -> folder |> Ecto.Changeset.change(name: name) |> Repo.update()
    end
  end

  def delete_folder(id, identity_id) do
    case Repo.get_by(DriveFolder, id: id, identity_id: identity_id) do
      nil -> {:error, :not_found}
      folder ->
        # Move children to parent folder
        DriveFolder
        |> where([f], f.parent_id == ^id)
        |> Repo.update_all(set: [parent_id: folder.parent_id])

        # Move files to parent folder
        MediaFile
        |> where([m], m.folder_id == ^id)
        |> Repo.update_all(set: [folder_id: folder.parent_id])

        Repo.delete(folder)
    end
  end

  # --- Files ---

  def list_files(identity_id, opts \\ []) do
    folder_id = Keyword.get(opts, :folder_id)
    limit = Keyword.get(opts, :limit, 30)
    max_id = Keyword.get(opts, :max_id)

    query =
      MediaFile
      |> where([m], m.identity_id == ^identity_id)

    query =
      if folder_id do
        where(query, [m], m.folder_id == ^folder_id)
      else
        where(query, [m], is_nil(m.folder_id))
      end

    query = if max_id, do: where(query, [m], m.id < ^max_id), else: query

    query
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def move_files(identity_id, file_ids, target_folder_id) do
    MediaFile
    |> where([m], m.identity_id == ^identity_id and m.id in ^file_ids)
    |> Repo.update_all(set: [folder_id: target_folder_id])
  end

  def find_by_hash(identity_id, hash) do
    MediaFile
    |> where([m], m.identity_id == ^identity_id and m.content_hash == ^hash)
    |> Repo.all()
  end

  def delete_files(identity_id, file_ids) do
    {count, _} =
      MediaFile
      |> where([m], m.identity_id == ^identity_id and m.id in ^file_ids)
      |> Repo.delete_all()

    {:ok, count}
  end

  def storage_usage(identity_id) do
    MediaFile
    |> where([m], m.identity_id == ^identity_id)
    |> select([m], %{count: count(m.id), total_bytes: sum(m.file_size)})
    |> Repo.one() || %{count: 0, total_bytes: 0}
  end
end

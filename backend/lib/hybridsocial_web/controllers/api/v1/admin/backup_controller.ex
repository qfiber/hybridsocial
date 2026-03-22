defmodule HybridsocialWeb.Api.V1.Admin.BackupController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Admin.Backup

  def create(conn, params) do
    admin_id = conn.assigns.current_identity.id
    passphrase = params["passphrase"]
    type = params["type"] || "full"

    if is_nil(passphrase) or passphrase == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "backup.passphrase_required"})
    else
      case Backup.create_backup(admin_id, passphrase, type) do
        {:ok, backup_job} ->
          conn
          |> put_status(:accepted)
          |> json(%{data: serialize_backup(backup_job)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation.failed", details: format_errors(changeset)})
      end
    end
  end

  def index(conn, _params) do
    backups = Backup.list_backups()

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(backups, &serialize_backup/1)})
  end

  def show(conn, %{"id" => id}) do
    case Backup.get_backup(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "backup.not_found"})

      backup_job ->
        conn
        |> put_status(:ok)
        |> json(%{data: serialize_backup(backup_job)})
    end
  end

  defp serialize_backup(backup_job) do
    %{
      id: backup_job.id,
      type: backup_job.type,
      status: backup_job.status,
      file_path: backup_job.file_path,
      file_size: backup_job.file_size,
      started_at: backup_job.started_at,
      completed_at: backup_job.completed_at,
      initiated_by: backup_job.initiated_by,
      created_at: backup_job.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

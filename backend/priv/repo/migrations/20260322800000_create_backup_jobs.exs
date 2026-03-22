defmodule Hybridsocial.Repo.Migrations.CreateBackupJobs do
  use Ecto.Migration

  def change do
    create table(:backup_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false, default: "full"
      add :status, :string, null: false, default: "pending"
      add :file_path, :string
      add :encryption_key_hash, :string
      add :file_size, :bigint
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :initiated_by, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:backup_jobs, [:initiated_by])
    create index(:backup_jobs, [:status])
  end
end

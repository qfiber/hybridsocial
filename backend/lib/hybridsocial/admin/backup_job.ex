defmodule Hybridsocial.Admin.BackupJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(full settings_only)
  @valid_statuses ~w(pending running completed failed)

  schema "backup_jobs" do
    field :type, :string, default: "full"
    field :status, :string, default: "pending"
    field :file_path, :string
    field :encryption_key_hash, :string
    field :file_size, :integer
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :initiator, Hybridsocial.Accounts.Identity, foreign_key: :initiated_by

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(backup_job, attrs) do
    backup_job
    |> cast(attrs, [
      :type,
      :status,
      :file_path,
      :encryption_key_hash,
      :file_size,
      :started_at,
      :completed_at,
      :initiated_by
    ])
    |> validate_required([:type, :status])
    |> validate_inclusion(:type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
  end
end

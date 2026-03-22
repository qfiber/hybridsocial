defmodule Hybridsocial.Portability.DataExport do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(pending processing completed failed)

  schema "data_exports" do
    field :status, :string, default: "pending"
    field :file_path, :string
    field :file_size, :integer
    field :requested_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(export, attrs) do
    export
    |> cast(attrs, [:identity_id, :status, :file_path, :file_size, :requested_at, :completed_at])
    |> validate_required([:identity_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:identity_id)
  end

  def complete_changeset(export, file_path, file_size) do
    export
    |> change(
      status: "completed",
      file_path: file_path,
      file_size: file_size,
      completed_at: DateTime.utc_now()
    )
  end

  def fail_changeset(export) do
    export
    |> change(status: "failed")
  end
end

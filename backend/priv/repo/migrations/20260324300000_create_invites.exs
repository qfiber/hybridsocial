defmodule Hybridsocial.Repo.Migrations.CreateInvites do
  use Ecto.Migration

  def change do
    create table(:invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :created_by, references(:identities, type: :binary_id, on_delete: :nilify_all)
      add :max_uses, :integer
      add :uses, :integer, default: 0, null: false
      add :expires_at, :utc_datetime_usec
      add :disabled, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invites, [:code])
    create index(:invites, [:created_by])
  end
end

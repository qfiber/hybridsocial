defmodule Hybridsocial.Repo.Migrations.CreateLists do
  use Ecto.Migration

  def change do
    create table(:lists, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:lists, [:identity_id])

    create table(:list_members, primary_key: false) do
      add :list_id, references(:lists, type: :binary_id, on_delete: :delete_all), null: false

      add :target_identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :added_at, :utc_datetime_usec, default: fragment("NOW()")
    end

    create unique_index(:list_members, [:list_id, :target_identity_id])
    create index(:list_members, [:target_identity_id])
  end
end

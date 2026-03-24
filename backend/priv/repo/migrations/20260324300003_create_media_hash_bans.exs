defmodule Hybridsocial.Repo.Migrations.CreateMediaHashBans do
  use Ecto.Migration

  def change do
    create table(:media_hash_bans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :hash, :string, null: false
      add :hash_type, :string, null: false, default: "sha256"
      add :description, :text
      add :created_by, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_hash_bans, [:hash, :hash_type])
    create index(:media_hash_bans, [:hash])
  end
end

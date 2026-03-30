defmodule Hybridsocial.Repo.Migrations.AddMarkers do
  use Ecto.Migration

  def change do
    create table(:markers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false
      add :timeline, :string, null: false
      add :last_read_id, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:markers, [:identity_id, :timeline])

    # Add expires_at to posts for activity expiration
    alter table(:posts) do
      add :expires_at, :utc_datetime_usec
    end

    create index(:posts, [:expires_at], where: "expires_at IS NOT NULL AND deleted_at IS NULL")
  end
end

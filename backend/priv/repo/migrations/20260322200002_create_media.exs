defmodule Hybridsocial.Repo.Migrations.CreateMedia do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE storage_backend AS ENUM ('local', 'S3')",
      "DROP TYPE storage_backend"
    )

    execute(
      "CREATE TYPE processing_status AS ENUM ('pending', 'processing', 'ready', 'failed')",
      "DROP TYPE processing_status"
    )

    create table(:media, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :content_type, :string, null: false
      add :file_size, :bigint, null: false
      add :storage_backend, :storage_backend, default: "local"
      add :storage_path, :string, null: false
      add :blurhash, :string
      add :alt_text, :text
      add :width, :integer
      add :height, :integer
      add :duration, :float
      add :thumbnail_path, :string
      add :processing_status, :processing_status, default: "pending"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
      add :deleted_at, :utc_datetime_usec
    end

    create index(:media, [:identity_id])
    create index(:media, [:processing_status])
    create index(:media, [:deleted_at])

    create table(:media_variants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :media_id, references(:media, type: :binary_id, on_delete: :delete_all),
        null: false

      add :resolution, :string
      add :storage_path, :string
      add :file_size, :bigint
      add :content_type, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:media_variants, [:media_id])
  end
end

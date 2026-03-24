defmodule Hybridsocial.Repo.Migrations.CreateAppealsAndModerationNotes do
  use Ecto.Migration

  def change do
    create table(:moderation_appeals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :action_type, :string, null: false
      add :reason, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :reviewed_by, references(:identities, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime_usec
      add :response, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:moderation_appeals, [:identity_id])
    create index(:moderation_appeals, [:status])
    create index(:moderation_appeals, [:identity_id, :action_type, :status])

    create table(:moderation_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :target_identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :content, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:moderation_notes, [:target_identity_id])
    create index(:moderation_notes, [:author_id])
  end
end

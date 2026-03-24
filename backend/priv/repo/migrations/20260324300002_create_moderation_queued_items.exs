defmodule Hybridsocial.Repo.Migrations.CreateModerationQueuedItems do
  use Ecto.Migration

  def change do
    create table(:moderation_queued_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :item_type, :string, null: false
      add :item_id, :binary_id, null: false
      add :source, :string, null: false
      add :reason, :text, null: false
      add :severity, :string, null: false, default: "medium"
      add :status, :string, null: false, default: "pending"
      add :reviewed_by, references(:identities, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:moderation_queued_items, [:status])
    create index(:moderation_queued_items, [:item_type])
    create index(:moderation_queued_items, [:severity])
    create index(:moderation_queued_items, [:item_type, :item_id])
    create index(:moderation_queued_items, [:status, :severity])
    create index(:moderation_queued_items, [:inserted_at])
  end
end

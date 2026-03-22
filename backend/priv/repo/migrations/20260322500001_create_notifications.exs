defmodule Hybridsocial.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :recipient_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :actor_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :type, :string, null: false
      add :target_type, :string
      add :target_id, :binary_id
      add :read, :boolean, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notifications, [:recipient_id])
    create index(:notifications, [:recipient_id, :read])
    create index(:notifications, [:actor_id])
    create index(:notifications, [:inserted_at])

    create table(:notification_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :type, :string, null: false
      add :email, :boolean, default: false
      add :push, :boolean, default: true
      add :in_app, :boolean, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notification_preferences, [:identity_id, :type])
  end
end

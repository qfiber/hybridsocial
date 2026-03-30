defmodule Hybridsocial.Repo.Migrations.AddMessagingFeatures do
  use Ecto.Migration

  def change do
    # Message reactions
    create table(:message_reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all), null: false
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :emoji, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:message_reactions, [:message_id, :identity_id, :emoji])
    create index(:message_reactions, [:message_id])

    # Chat acceptance flow
    alter table(:conversations) do
      add :accepted, :boolean, default: false
      add :created_by_id, references(:identities, type: :binary_id, on_delete: :nilify_all)
      add :is_local, :boolean, default: true
    end

    # Add accepted=true default for existing conversations
    execute "UPDATE conversations SET accepted = true", ""
  end
end

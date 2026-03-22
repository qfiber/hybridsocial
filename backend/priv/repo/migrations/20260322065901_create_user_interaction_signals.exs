defmodule Hybridsocial.Repo.Migrations.CreateUserInteractionSignals do
  use Ecto.Migration

  def change do
    create table(:user_interaction_signals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :target_identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :interaction_count, :integer, default: 0
      add :last_interaction, :utc_datetime_usec
      add :content_tags, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_interaction_signals, [:identity_id, :target_identity_id])
  end
end

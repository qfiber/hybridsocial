defmodule Hybridsocial.Repo.Migrations.CreatePushSubscriptions do
  use Ecto.Migration

  def change do
    create table(:push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :endpoint, :string, null: false
      add :key_p256dh, :string, null: false
      add :key_auth, :string, null: false
      add :user_agent, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:push_subscriptions, [:identity_id])
    create unique_index(:push_subscriptions, [:identity_id, :endpoint])
  end
end

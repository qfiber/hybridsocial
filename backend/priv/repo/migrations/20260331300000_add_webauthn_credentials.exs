defmodule Hybridsocial.Repo.Migrations.AddWebauthnCredentials do
  use Ecto.Migration

  def change do
    create table(:webauthn_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :credential_id, :text, null: false
      add :public_key, :text, null: false
      add :sign_count, :integer, default: 0
      add :name, :string, default: "Security Key"
      add :last_used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:webauthn_credentials, [:credential_id])
    create index(:webauthn_credentials, [:identity_id])
  end
end

defmodule Hybridsocial.Repo.Migrations.CreateOauthAuthorizationCodes do
  use Ecto.Migration

  def change do
    create table(:oauth_authorization_codes, primary_key: false) do
      add :code_hash, :string, primary_key: true
      add :application_id, references(:oauth_applications, type: :binary_id, on_delete: :delete_all),
        null: false
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false
      add :redirect_uri, :string, null: false
      add :scopes, {:array, :string}, default: []
      add :code_challenge, :string, null: false
      add :code_challenge_method, :string, default: "S256", null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:oauth_authorization_codes, [:application_id])
    create index(:oauth_authorization_codes, [:identity_id])
    create index(:oauth_authorization_codes, [:expires_at])
  end
end

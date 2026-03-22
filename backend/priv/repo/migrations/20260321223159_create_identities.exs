defmodule Hybridsocial.Repo.Migrations.CreateIdentities do
  use Ecto.Migration

  def change do
    # Custom enum types
    execute(
      "CREATE TYPE identity_type AS ENUM ('user', 'organization')",
      "DROP TYPE identity_type"
    )

    # Core identity table — shared across all actor types
    create table(:identities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :identity_type, null: false
      add :handle, :string, null: false
      add :ap_actor_url, :string
      add :public_key, :text
      add :private_key, :text
      add :inbox_url, :string
      add :outbox_url, :string
      add :followers_url, :string
      add :avatar_url, :string
      add :header_url, :string
      add :display_name, :string
      add :bio, :text
      add :metadata, :map, default: %{}
      add :is_locked, :boolean, default: false
      add :is_bot, :boolean, default: false
      add :is_suspended, :boolean, default: false
      add :suspended_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
      add :deleted_at, :utc_datetime_usec
    end

    create unique_index(:identities, [:handle])
    create unique_index(:identities, [:ap_actor_url])
    create index(:identities, [:type])
    create index(:identities, [:deleted_at])

    # Handle history — prevent impersonation after handle changes
    create table(:handle_history, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :old_handle, :string, null: false
      add :changed_at, :utc_datetime_usec, null: false
      add :reserved_until, :utc_datetime_usec, null: false
    end

    create index(:handle_history, [:identity_id])
    create index(:handle_history, [:old_handle])
    create index(:handle_history, [:reserved_until])

    # User-specific details
    create table(:users, primary_key: false) do
      add :identity_id,
          references(:identities, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :locale, :string, default: "en"
      add :timezone, :string
      add :last_login_at, :utc_datetime_usec
      add :confirmed_at, :utc_datetime_usec
      add :confirmation_token, :string
      add :confirmation_sent_at, :utc_datetime_usec
      add :reset_token, :string
      add :reset_token_at, :utc_datetime_usec
      add :otp_secret, :string
      add :otp_enabled, :boolean, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
    create index(:users, [:confirmation_token])
    create index(:users, [:reset_token])

    # Organization/Page-specific details
    create table(:organizations, primary_key: false) do
      add :identity_id,
          references(:identities, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :owner_id, references(:identities, type: :binary_id, on_delete: :nilify_all)
      add :website, :string
      add :category, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:organizations, [:owner_id])

    # Organization roles
    execute(
      "CREATE TYPE org_role AS ENUM ('admin', 'editor', 'moderator')",
      "DROP TYPE org_role"
    )

    create table(:organization_roles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations,
            column: :identity_id,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role, :org_role, null: false

      add :granted_by, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_roles, [:organization_id, :identity_id])
    create index(:organization_roles, [:identity_id])

    # OAuth applications
    create table(:oauth_applications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :client_id, :string, null: false
      add :client_secret_hash, :string, null: false
      add :redirect_uris, {:array, :string}, default: []
      add :scopes, {:array, :string}, default: []
      add :website, :string
      add :created_by, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:oauth_applications, [:client_id])

    # OAuth tokens
    create table(:oauth_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :application_id,
          references(:oauth_applications, type: :binary_id, on_delete: :delete_all)

      add :token_hash, :string, null: false
      add :refresh_token_hash, :string
      add :scopes, {:array, :string}, default: []
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:oauth_tokens, [:token_hash])
    create unique_index(:oauth_tokens, [:refresh_token_hash])
    create index(:oauth_tokens, [:identity_id])
    create index(:oauth_tokens, [:expires_at])

    # Instance settings (runtime configuration)
    create table(:instance_settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :map, null: false
      add :type, :string, null: false, default: "string"
      add :category, :string, null: false, default: "general"
      add :description, :text
      add :updated_by, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:instance_settings, [:category])
  end
end

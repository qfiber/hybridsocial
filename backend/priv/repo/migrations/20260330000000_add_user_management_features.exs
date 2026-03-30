defmodule Hybridsocial.Repo.Migrations.AddUserManagementFeatures do
  use Ecto.Migration

  def change do
    # User-level domain blocks
    create table(:user_domain_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :domain, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_domain_blocks, [:identity_id, :domain])
    create index(:user_domain_blocks, [:identity_id])

    # Personal account notes (user-to-user, not moderation)
    create table(:account_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :author_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :target_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :content, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:account_notes, [:author_id, :target_id])

    # Suggested users flag
    alter table(:identities) do
      add :is_suggested, :boolean, default: false
      add :is_name_revoked, :boolean, default: false
    end

    # Account approval (add approved_at to users table)
    alter table(:users) do
      add :approved_at, :utc_datetime_usec
      add :approval_required, :boolean, default: false
    end

    # Set existing users as approved
    execute "UPDATE users SET approved_at = confirmed_at WHERE confirmed_at IS NOT NULL", ""
  end
end

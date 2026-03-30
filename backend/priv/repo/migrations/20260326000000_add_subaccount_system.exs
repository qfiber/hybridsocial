defmodule Hybridsocial.Repo.Migrations.AddSubaccountSystem do
  use Ecto.Migration

  def up do
    # 1. Expand identity_type enum with bot and group
    execute("ALTER TYPE identity_type ADD VALUE IF NOT EXISTS 'bot'")
    execute("ALTER TYPE identity_type ADD VALUE IF NOT EXISTS 'group'")

    # 2. Add parent_identity_id to identities for subaccount hierarchy
    alter table(:identities) do
      add :parent_identity_id, references(:identities, type: :binary_id, on_delete: :nothing)
    end

    create index(:identities, [:parent_identity_id])

    # 3. Create bots table for bot-specific configuration
    create table(:bots, primary_key: false) do
      add :identity_id,
          references(:identities, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :webhook_url, :string
      add :webhook_secret_hash, :string
      add :auto_approve_follows, :boolean, default: false
      add :description, :text
      add :source_code_url, :string
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime_usec)
    end

    # 4. Add identity_id to groups to link them to the identity system
    alter table(:groups) do
      add :identity_id, references(:identities, type: :binary_id, on_delete: :nothing)
    end

    create unique_index(:groups, [:identity_id])

    # 5. Add composite index for efficient subaccount queries
    create index(:identities, [:parent_identity_id, :type])
  end

  def down do
    # Remove group identity link
    drop_if_exists index(:groups, [:identity_id])

    alter table(:groups) do
      remove :identity_id
    end

    # Remove bots table
    drop_if_exists table(:bots)

    # Remove parent identity link
    drop_if_exists index(:identities, [:parent_identity_id, :type])
    drop_if_exists index(:identities, [:parent_identity_id])

    alter table(:identities) do
      remove :parent_identity_id
    end

    # Note: Cannot remove enum values in PostgreSQL without recreating the type.
    # The 'bot' and 'group' values will remain in the enum.
  end
end

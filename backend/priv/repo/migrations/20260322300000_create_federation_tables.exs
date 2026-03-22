defmodule Hybridsocial.Repo.Migrations.CreateFederationTables do
  use Ecto.Migration

  def up do
    execute(
      "CREATE TYPE instance_policy_type AS ENUM ('allow', 'silence', 'suspend', 'block_media', 'force_nsfw')"
    )

    execute("CREATE TYPE delivery_status AS ENUM ('pending', 'delivered', 'failed', 'retrying')")
    execute("CREATE TYPE relay_status AS ENUM ('pending', 'accepted', 'rejected')")

    create table(:remote_actors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ap_id, :string, null: false
      add :handle, :string
      add :domain, :string
      add :display_name, :string
      add :avatar_url, :string
      add :public_key, :text
      add :inbox_url, :string
      add :outbox_url, :string
      add :followers_url, :string
      add :shared_inbox_url, :string
      add :last_fetched_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:remote_actors, [:ap_id])
    create index(:remote_actors, [:domain])

    create table(:instance_policies, primary_key: false) do
      add :domain, :string, primary_key: true
      add :policy, :instance_policy_type, null: false
      add :reason, :text
      add :created_by, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:federation_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :activity_id, :string
      add :actor_id, :binary_id
      add :target_inbox, :string
      add :status, :delivery_status, null: false, default: "pending"
      add :attempts, :integer, default: 0
      add :last_attempt_at, :utc_datetime_usec
      add :error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:federation_deliveries, [:activity_id])
    create index(:federation_deliveries, [:status])

    create table(:federation_dedup, primary_key: false) do
      add :activity_hash, :string, primary_key: true
      add :activity_id, :string
      add :processed_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
    end

    create index(:federation_dedup, [:expires_at])

    create table(:relays, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :inbox_url, :string, null: false
      add :status, :relay_status, null: false, default: "pending"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:relays, [:inbox_url])
  end

  def down do
    drop table(:relays)
    drop table(:federation_dedup)
    drop table(:federation_deliveries)
    drop table(:instance_policies)
    drop table(:remote_actors)

    execute("DROP TYPE relay_status")
    execute("DROP TYPE delivery_status")
    execute("DROP TYPE instance_policy_type")
  end
end

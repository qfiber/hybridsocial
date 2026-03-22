defmodule Hybridsocial.Repo.Migrations.CreateSocialGraph do
  use Ecto.Migration

  def up do
    execute("CREATE TYPE follow_status AS ENUM ('pending', 'accepted', 'rejected')")

    create table(:follows, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :follower_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :followee_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :follow_status, null: false, default: "pending"
      add :notify, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:follows, [:follower_id, :followee_id])
    create index(:follows, [:followee_id])

    create table(:blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :blocker_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :blocked_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:blocks, [:blocker_id, :blocked_id])
    create index(:blocks, [:blocked_id])

    create table(:mutes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :muter_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :muted_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mute_notifications, :boolean, default: true, null: false
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:mutes, [:muter_id, :muted_id])
    create index(:mutes, [:muted_id])
  end

  def down do
    drop table(:mutes)
    drop table(:blocks)
    drop table(:follows)
    execute("DROP TYPE follow_status")
  end
end

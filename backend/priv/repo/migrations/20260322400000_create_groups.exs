defmodule Hybridsocial.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def up do
    execute("CREATE TYPE group_visibility AS ENUM ('public', 'private', 'local_only')")
    execute("CREATE TYPE group_join_policy AS ENUM ('open', 'screening', 'approval', 'invite_only')")
    execute("CREATE TYPE group_member_role AS ENUM ('member', 'moderator', 'admin', 'owner')")
    execute("CREATE TYPE group_member_status AS ENUM ('pending', 'approved', 'rejected', 'banned')")
    execute("CREATE TYPE group_application_status AS ENUM ('pending', 'approved', 'rejected', 'auto_approved')")

    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :visibility, :group_visibility, default: "public"
      add :join_policy, :group_join_policy, default: "open"
      add :ap_actor_url, :string
      add :public_key, :text
      add :private_key, :text
      add :avatar_url, :string
      add :header_url, :string
      add :member_count, :integer, default: 0
      add :post_count, :integer, default: 0
      add :created_by, references(:identities, type: :binary_id, on_delete: :nothing), null: false
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:groups, [:visibility])
    create index(:groups, [:deleted_at])

    create table(:group_screening_config, primary_key: false) do
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), primary_key: true
      add :require_profile_image, :boolean, default: false
      add :min_account_age_days, :integer, default: 0
      add :questions, :jsonb, default: "[]"
      add :auto_approve_rules, :jsonb, default: "{}"
    end

    create table(:group_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :group_member_role, default: "member"
      add :status, :group_member_status, default: "approved"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_members, [:group_id, :identity_id])

    create table(:group_applications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :answers, :jsonb, default: "{}"
      add :status, :group_application_status, default: "pending"
      add :reviewed_by, references(:identities, type: :binary_id, on_delete: :nothing)
      add :created_at, :utc_datetime_usec, default: fragment("now()")
      add :reviewed_at, :utc_datetime_usec
    end

    create table(:group_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false
      add :invited_by, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :invited_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, default: "pending"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:group_invites, [:group_id, :invited_id])
  end

  def down do
    drop table(:group_invites)
    drop table(:group_applications)
    drop table(:group_members)
    drop table(:group_screening_config)
    drop table(:groups)

    execute("DROP TYPE group_application_status")
    execute("DROP TYPE group_member_status")
    execute("DROP TYPE group_member_role")
    execute("DROP TYPE group_join_policy")
    execute("DROP TYPE group_visibility")
  end
end

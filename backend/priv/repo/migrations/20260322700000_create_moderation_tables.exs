defmodule Hybridsocial.Repo.Migrations.CreateModerationTables do
  use Ecto.Migration

  def up do
    # Enums
    execute "CREATE TYPE report_category AS ENUM ('spam', 'harassment', 'hate_speech', 'illegal', 'misinformation', 'other')"

    execute "CREATE TYPE report_status AS ENUM ('pending', 'investigating', 'resolved', 'dismissed')"

    execute "CREATE TYPE filter_action AS ENUM ('flag', 'reject', 'replace')"
    execute "CREATE TYPE filter_context AS ENUM ('posts', 'usernames', 'bios', 'all')"
    execute "CREATE TYPE banned_domain_type AS ENUM ('email', 'federation', 'both')"

    # Reports
    create table(:reports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :reporter_id, references(:identities, type: :binary_id, on_delete: :nothing),
        null: false

      add :reported_id, references(:identities, type: :binary_id, on_delete: :nothing),
        null: false

      add :target_type, :string
      add :target_id, :binary_id
      add :category, :report_category, null: false
      add :description, :text
      add :status, :report_status, default: "pending"
      add :assigned_to, references(:identities, type: :binary_id, on_delete: :nothing)
      add :action_taken, :string
      add :federated, :boolean, default: false
      add :resolved_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:reports, [:status])
    create index(:reports, [:reported_id])
    create index(:reports, [:reporter_id])

    # Audit Log (BIGSERIAL primary key, immutable - no updated_at)
    create table(:audit_log) do
      add :actor_id, references(:identities, type: :binary_id, on_delete: :nothing)
      add :action, :string, null: false
      add :target_type, :string
      add :target_id, :binary_id
      add :details, :map, default: %{}
      add :ip_address, :string
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:audit_log, [:actor_id])
    create index(:audit_log, [:action])
    create index(:audit_log, [:created_at])

    # Content Filters
    create table(:content_filters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :pattern, :string, null: false
      add :action, :filter_action, null: false
      add :replacement, :string
      add :context, :filter_context, default: "all"
      add :created_by, references(:identities, type: :binary_id, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    # Banned Domains (primary key is the domain string)
    create table(:banned_domains, primary_key: false) do
      add :domain, :string, primary_key: true
      add :type, :banned_domain_type, null: false
      add :reason, :text
      add :created_by, references(:identities, type: :binary_id, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    # Moderation Webhooks
    create table(:moderation_webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :string, null: false
      add :events, {:array, :string}, default: []
      add :secret, :string
      add :enabled, :boolean, default: true
      add :created_by, references(:identities, type: :binary_id, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end
  end

  def down do
    drop table(:moderation_webhooks)
    drop table(:banned_domains)
    drop table(:content_filters)
    drop table(:audit_log)
    drop table(:reports)

    execute "DROP TYPE banned_domain_type"
    execute "DROP TYPE filter_context"
    execute "DROP TYPE filter_action"
    execute "DROP TYPE report_status"
    execute "DROP TYPE report_category"
  end
end

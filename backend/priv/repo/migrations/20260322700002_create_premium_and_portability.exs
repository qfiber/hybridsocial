defmodule Hybridsocial.Repo.Migrations.CreatePremiumAndPortability do
  use Ecto.Migration

  def change do
    create table(:verifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :verified_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:verifications, [:identity_id])

    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :plan, :string, null: false, default: "free"
      add :status, :string, null: false, default: "active"
      add :payment_provider, :string
      add :external_id, :string
      add :started_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:subscriptions, [:identity_id])

    create table(:instance_funding, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :platform, :string, null: false
      add :config, :map, default: %{}
      add :enabled, :boolean, default: false
      add :display_text, :string
      add :goal_amount, :decimal
      add :current_amount, :decimal, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create table(:donations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :donor_id, references(:identities, type: :binary_id, on_delete: :nilify_all)
      add :amount, :decimal, null: false
      add :currency, :string, size: 3, null: false
      add :platform, :string
      add :transaction_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:donations, [:donor_id])

    create table(:data_exports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, default: "pending"
      add :file_path, :string
      add :file_size, :bigint
      add :requested_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:data_exports, [:identity_id])

    create table(:account_deletions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :reason, :text
      add :scheduled_for, :utc_datetime_usec, null: false
      add :cancelled_at, :utc_datetime_usec
      add :executed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:account_deletions, [:identity_id])
  end
end

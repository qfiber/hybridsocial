defmodule Hybridsocial.Repo.Migrations.CreatePromotions do
  use Ecto.Migration

  def change do
    create table(:promotions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "pending"
      add :payment_provider, :string
      add :payment_id, :string
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false, default: "USD"
      add :duration_days, :integer, null: false
      add :starts_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:promotions, [:identity_id])
    create index(:promotions, [:status])
    create index(:promotions, [:expires_at], where: "status = 'active'")
  end
end

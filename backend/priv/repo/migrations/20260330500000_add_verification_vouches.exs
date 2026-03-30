defmodule Hybridsocial.Repo.Migrations.AddVerificationVouches do
  use Ecto.Migration

  def change do
    create table(:verification_vouches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :verification_id, references(:verifications, type: :binary_id, on_delete: :delete_all), null: false
      add :voucher_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:verification_vouches, [:verification_id, :voucher_id])
    create index(:verification_vouches, [:voucher_id])
  end
end

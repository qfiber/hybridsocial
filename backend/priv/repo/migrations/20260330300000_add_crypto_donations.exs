defmodule Hybridsocial.Repo.Migrations.AddCryptoDonations do
  use Ecto.Migration

  def change do
    # Crypto wallet addresses for users (profile-level)
    create table(:crypto_addresses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :coin, :string, null: false  # btc, eth, xmr, sol, etc.
      add :address, :string, null: false
      add :label, :string  # optional label like "Main wallet"
      add :is_public, :boolean, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create index(:crypto_addresses, [:identity_id])
    create unique_index(:crypto_addresses, [:identity_id, :coin])
  end
end

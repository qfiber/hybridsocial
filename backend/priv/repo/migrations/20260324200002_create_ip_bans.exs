defmodule Hybridsocial.Repo.Migrations.CreateIpBans do
  use Ecto.Migration

  def change do
    create table(:ip_bans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ip_address, :string, null: false
      add :subnet_mask, :string
      add :reason, :text
      add :expires_at, :utc_datetime_usec
      add :created_by, references(:identities, type: :binary_id, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ip_bans, [:ip_address])
    create index(:ip_bans, [:expires_at])
  end
end

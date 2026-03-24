defmodule Hybridsocial.Repo.Migrations.CreateEmailDomainBans do
  use Ecto.Migration

  def change do
    create table(:email_domain_bans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :domain, :string, null: false
      add :reason, :text
      add :created_by, references(:identities, type: :binary_id, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:email_domain_bans, [:domain])
  end
end

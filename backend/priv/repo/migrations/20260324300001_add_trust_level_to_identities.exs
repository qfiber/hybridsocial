defmodule Hybridsocial.Repo.Migrations.AddTrustLevelToIdentities do
  use Ecto.Migration

  def change do
    alter table(:identities) do
      add :trust_level, :integer, default: 0, null: false
    end

    create index(:identities, [:trust_level])
  end
end

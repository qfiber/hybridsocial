defmodule Hybridsocial.Repo.Migrations.AddVerificationTiers do
  use Ecto.Migration

  def change do
    alter table(:identities) do
      add :verification_tier, :string, default: "free"
    end

    create index(:identities, [:verification_tier])
  end
end

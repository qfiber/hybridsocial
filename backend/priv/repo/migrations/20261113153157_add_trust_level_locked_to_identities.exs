defmodule Hybridsocial.Repo.Migrations.AddTrustLevelLockedToIdentities do
  use Ecto.Migration

  # A trust level set by staff is pinned: the automatic recompute
  # (`Accounts.Trust.refresh_trust_level/1`) leaves it alone (#67).
  def change do
    alter table(:identities) do
      add :trust_level_locked, :boolean, null: false, default: false
    end
  end
end

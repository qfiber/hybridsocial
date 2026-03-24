defmodule Hybridsocial.Repo.Migrations.AddShowBadgeToIdentities do
  use Ecto.Migration

  def change do
    alter table(:identities) do
      add :show_badge, :boolean, default: true
    end
  end
end

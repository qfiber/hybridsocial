defmodule Hybridsocial.Repo.Migrations.AddIsAdminToIdentities do
  use Ecto.Migration

  def change do
    alter table(:identities) do
      add :is_admin, :boolean, default: false
    end
  end
end

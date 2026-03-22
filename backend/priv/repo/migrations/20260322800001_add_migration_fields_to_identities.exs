defmodule Hybridsocial.Repo.Migrations.AddMigrationFieldsToIdentities do
  use Ecto.Migration

  def change do
    alter table(:identities) do
      add :also_known_as, {:array, :string}, default: []
      add :moved_to, :string
    end
  end
end

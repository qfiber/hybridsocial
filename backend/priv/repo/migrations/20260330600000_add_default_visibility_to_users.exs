defmodule Hybridsocial.Repo.Migrations.AddPreferencesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :default_visibility, :string, default: "public"
      add :preferences, :map, default: %{}
    end
  end
end

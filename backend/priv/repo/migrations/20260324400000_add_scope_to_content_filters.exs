defmodule Hybridsocial.Repo.Migrations.AddScopeToContentFilters do
  use Ecto.Migration

  def change do
    alter table(:content_filters) do
      add :scope, :string, null: false, default: "all"
    end
  end
end

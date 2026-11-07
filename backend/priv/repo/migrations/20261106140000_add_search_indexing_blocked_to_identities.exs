defmodule Hybridsocial.Repo.Migrations.AddSearchIndexingBlockedToIdentities do
  use Ecto.Migration

  def change do
    # Set by staff, so it lives apart from the fields a user can edit.
    alter table(:identities) do
      add :search_indexing_blocked, :boolean, null: false, default: false
    end
  end
end

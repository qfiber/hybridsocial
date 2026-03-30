defmodule Hybridsocial.Repo.Migrations.AddParentApIdToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :parent_ap_id, :text
    end

    create index(:posts, [:parent_ap_id])
  end
end

defmodule Hybridsocial.Repo.Migrations.AddApIdToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :ap_id, :string
    end

    create unique_index(:posts, [:ap_id], where: "ap_id IS NOT NULL")
  end
end

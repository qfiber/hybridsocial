defmodule Hybridsocial.Repo.Migrations.AddExcerpts do
  use Ecto.Migration

  def change do
    create table(:excerpts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :keywords, {:array, :string}, default: []
      add :exclude_keywords, {:array, :string}, default: []
      add :sources, {:array, :string}, default: ["home", "local", "global"]
      add :with_media_only, :boolean, default: false
      add :notify, :boolean, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:excerpts, [:identity_id])
  end
end

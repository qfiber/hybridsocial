defmodule Hybridsocial.Repo.Migrations.AddBoostMutes do
  use Ecto.Migration

  def change do
    create table(:boost_mutes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :muter_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false
      add :target_id, references(:identities, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:boost_mutes, [:muter_id, :target_id])
  end
end
